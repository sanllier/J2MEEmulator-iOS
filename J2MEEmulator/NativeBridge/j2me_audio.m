//
// j2me_audio.m — Audio bridge: AVAudioPlayer (WAV/MP3) + AVMIDIPlayer (MIDI)
//
// Maps J2ME media API to iOS AVFoundation.
// Analogous to J2ME-Loader's mapping to Android MediaPlayer + MidiDriver.
//

#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#include "j2me_audio.h"
#include "jvm.h"
#include "jvm_util.h"
#include <stdio.h>

// ============================================================
// Native heap accounting — feeds gc_sum_heap so miniJVM can see
// audio-buffer pressure and trigger GC reactively. Without this
// a game with hundreds of MB of decoded PCM looks like a tiny
// Java heap to the collector.
// ============================================================
extern s64 g_native_extra_heap;  // defined in minijvm/jvm/garbage.c

static inline void audio_heap_add(s64 bytes) {
    if (bytes > 0) __atomic_fetch_add(&g_native_extra_heap, bytes, __ATOMIC_RELAXED);
}
static inline void audio_heap_sub(s64 bytes) {
    if (bytes > 0) __atomic_fetch_sub(&g_native_extra_heap, bytes, __ATOMIC_RELAXED);
}

// Each tracked player carries its source-buffer size as an associated
// object — that way release sites don't need to look it up out of band.
static const void *kPlayerHeapBytesKey = &kPlayerHeapBytesKey;

static void set_player_heap_bytes(id player, s64 bytes) {
    objc_setAssociatedObject(player, kPlayerHeapBytesKey, @(bytes),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static s64 take_player_heap_bytes(id player) {
    NSNumber *n = objc_getAssociatedObject(player, kPlayerHeapBytesKey);
    if (!n) return 0;
    s64 bytes = (s64)[n longLongValue];
    objc_setAssociatedObject(player, kPlayerHeapBytesKey, nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return bytes;
}

// ============================================================
// Audio session setup
// ============================================================
//
// We activate the shared AVAudioSession once per app lifetime and never
// tear it down. Earlier code deactivated it on j2me_audio_stop_all
// (between MIDlets), but setActive:NO with NotifyOthersOnDeactivation is
// asynchronous: setActive:YES on the next MIDlet would return success
// while the session was still mid-deactivate, and AVMIDIPlayer's internal
// AudioUnit setup would then fail with kAudioUnitErr_InvalidPropertyValue
// (-10851), silently losing MIDI playback for the rest of the session.
// Apple's apps generally leave the session active for the app's lifetime.

// Re-activate the shared audio session after a system interruption (incoming
// call, Siri, alarm). iOS deactivates our session for the duration of the
// interruption and does NOT silently restore it afterwards — without an
// explicit setActive:YES every subsequent AVAudioPlayer / AVMIDIPlayer play()
// stays silent for the rest of the MIDlet's life.
static void reactivateAudioSession(void) {
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&err];
    if (err) {
        printf("[J2ME Audio] interruption reactivate error: %s\n",
               [[err localizedDescription] UTF8String]);
    } else {
        printf("[J2ME Audio] audio session reactivated after interruption\n");
    }
}

static void ensureAudioSession(void) {
    static BOOL initialized = NO;
    if (initialized) return;
    NSError *catErr = nil, *actErr = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&catErr];
    [[AVAudioSession sharedInstance] setActive:YES error:&actErr];
    if (catErr) {
        printf("[J2ME Audio] setCategory error: %s\n",
               [[catErr localizedDescription] UTF8String]);
    }
    if (actErr) {
        printf("[J2ME Audio] setActive error: %s — will retry on next play\n",
               [[actErr localizedDescription] UTF8String]);
        return; // leave initialized=NO so a subsequent play tries again
    }

    // Subscribe once for the app's lifetime — when an interruption ends and
    // the system says we should resume, re-activate the session. The block
    // runs on the main queue, so setActive: is called off the JVM thread.
    [[NSNotificationCenter defaultCenter]
        addObserverForName:AVAudioSessionInterruptionNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *note) {
        NSNumber *typeVal = note.userInfo[AVAudioSessionInterruptionTypeKey];
        if (typeVal.unsignedIntegerValue != AVAudioSessionInterruptionTypeEnded) return;
        NSNumber *optsVal = note.userInfo[AVAudioSessionInterruptionOptionKey];
        if (optsVal &&
            (optsVal.unsignedIntegerValue & AVAudioSessionInterruptionOptionShouldResume)) {
            reactivateAudioSession();
        }
    }];

    initialized = YES;
}

// ============================================================
// SoundFont path for MIDI
// ============================================================

static NSURL *getSoundFontURL(void) {
    static NSURL *url = nil;
    if (!url) {
        // Try various subdirectory locations
        url = [[NSBundle mainBundle] URLForResource:@"gs_instruments" withExtension:@"sf2"];
        if (!url) {
            url = [[NSBundle mainBundle] URLForResource:@"gs_instruments" withExtension:@"sf2"
                                           subdirectory:@"sound_fonts"];
        }
        if (!url) {
            url = [[NSBundle mainBundle] URLForResource:@"gs_instruments" withExtension:@"sf2"
                                           subdirectory:@"Resources/sound_fonts"];
        }
        if (!url) {
            // Brute-force search
            NSString *path = [[NSBundle mainBundle] pathForResource:@"gs_instruments" ofType:@"sf2"];
            if (path) url = [NSURL fileURLWithPath:path];
        }
        if (!url) {
            printf("[J2ME Audio] WARNING: gs_instruments.sf2 not found in bundle!\n");
        }
    }
    return url;
}

// ============================================================
// Audio completion delegate
// ============================================================

// Event type for END_OF_MEDIA posted to input queue
#define J2ME_AUDIO_END_OF_MEDIA 13

@interface J2MEAudioDelegate : NSObject <AVAudioPlayerDelegate>
@end

@implementation J2MEAudioDelegate
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    // Post END_OF_MEDIA event to input queue
    j2me_input_post_key(J2ME_AUDIO_END_OF_MEDIA, 0);
}
@end

static J2MEAudioDelegate *g_audioDelegate = nil;

static J2MEAudioDelegate *getAudioDelegate(void) {
    if (!g_audioDelegate) {
        g_audioDelegate = [[J2MEAudioDelegate alloc] init];
    }
    return g_audioDelegate;
}

// ============================================================
// Active player tracking (for cleanup between game sessions)
// ============================================================

static NSMutableSet *g_active_audio_players = nil;
static NSMutableSet *g_active_midi_players = nil;

static void track_audio_player(AVAudioPlayer *player) {
    @synchronized ([AVAudioSession class]) {
        if (!g_active_audio_players) g_active_audio_players = [NSMutableSet new];
        [g_active_audio_players addObject:player];
    }
}

// Returns YES iff this caller actually removed the player from the tracking set
// (only the remover owns the CFRetain and must do the matching CFRelease).
// This races with j2me_audio_stop_all, which also drains the set under the same lock.
static BOOL claim_audio_player(AVAudioPlayer *player) {
    @synchronized ([AVAudioSession class]) {
        if (g_active_audio_players && [g_active_audio_players containsObject:player]) {
            [g_active_audio_players removeObject:player];
            return YES;
        }
        return NO;
    }
}

static void track_midi_player(AVMIDIPlayer *player) {
    @synchronized ([AVAudioSession class]) {
        if (!g_active_midi_players) g_active_midi_players = [NSMutableSet new];
        [g_active_midi_players addObject:player];
    }
}

static BOOL claim_midi_player(AVMIDIPlayer *player) {
    @synchronized ([AVAudioSession class]) {
        if (g_active_midi_players && [g_active_midi_players containsObject:player]) {
            [g_active_midi_players removeObject:player];
            return YES;
        }
        return NO;
    }
}

void j2me_audio_stop_all(void) {
    NSSet *midiSnapshot = nil;

    @synchronized ([AVAudioSession class]) {
        if (g_active_audio_players) {
            for (AVAudioPlayer *p in [g_active_audio_players copy]) {
                [p stop];
                audio_heap_sub(take_player_heap_bytes(p));
                CFRelease((__bridge CFTypeRef)p);
            }
            [g_active_audio_players removeAllObjects];
        }
        if (g_active_midi_players) {
            // Take a snapshot and clear the tracking set while holding the lock.
            // Actual stop+release of MIDI players must happen on the main thread
            // because AVMIDIPlayer's internal AUGraph asserts during dealloc if
            // the AudioUnit is still in a render callback on another thread.
            midiSnapshot = [g_active_midi_players copy];
            [g_active_midi_players removeAllObjects];
        }
    }

    if (midiSnapshot.count > 0) {
        void (^drainMidi)(void) = ^{
            for (AVMIDIPlayer *p in midiSnapshot) {
                [p stop];
                audio_heap_sub(take_player_heap_bytes(p));
                CFRelease((__bridge CFTypeRef)p);
            }
        };
        if ([NSThread isMainThread]) {
            drainMidi();
        } else {
            dispatch_sync(dispatch_get_main_queue(), drainMidi);
        }
    }

    // Note: we deliberately do NOT call setActive:NO here. Deactivation
    // is async (NotifyOthersOnDeactivation in particular), and a quick
    // reactivate in the next MIDlet races the async teardown — AVMIDIPlayer
    // then fails to bring up its AudioUnit and silently disables MIDI.
    // Leaving the session active across MIDlets is the standard pattern
    // for iOS audio apps and incurs no measurable hardware cost.

    printf("[J2ME Audio] All players stopped and released\n");
}

// ============================================================
// WAV/MP3 — AVAudioPlayer
// ============================================================

static s32 n_audioCreatePlayer(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    Instance *arr = env->localvar_getRefer(runtime->localvar, 0);

    if (!arr) { env->push_long(runtime->stack, 0); return RUNTIME_STATUS_NORMAL; }

    ensureAudioSession();

    s32 length = arr->arr_length;
    NSData *data = [NSData dataWithBytes:arr->arr_body length:length];

    NSError *error = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithData:data error:&error];
    if (error || !player) {
        printf("[J2ME Audio] AVAudioPlayer init error: %s\n",
               error ? [[error localizedDescription] UTF8String] : "nil");
        env->push_long(runtime->stack, 0);
        return RUNTIME_STATUS_NORMAL;
    }

    player.delegate = getAudioDelegate();
    [player prepareToPlay];
    // Prevent ARC from releasing — bridge retain
    CFRetain((__bridge CFTypeRef)player);
    track_audio_player(player);
    set_player_heap_bytes(player, length);
    audio_heap_add(length);
    env->push_long(runtime->stack, (s64)(intptr_t)(__bridge void *)player);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioStart(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    if (handle) {
        AVAudioPlayer *player = (__bridge AVAudioPlayer *)(void *)(intptr_t)handle;
        [player play];
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioStop(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    if (handle) {
        AVAudioPlayer *player = (__bridge AVAudioPlayer *)(void *)(intptr_t)handle;
        [player pause];
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioClose(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    if (handle) {
        AVAudioPlayer *player = (__bridge AVAudioPlayer *)(void *)(intptr_t)handle;
        if (claim_audio_player(player)) {
            [player stop];
            audio_heap_sub(take_player_heap_bytes(player));
            CFRelease((__bridge CFTypeRef)player);
        }
        // else: j2me_audio_stop_all already took ownership; do nothing.
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioSetLoop(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    s32 count = env->localvar_getInt(runtime->localvar, 2);
    if (handle) {
        AVAudioPlayer *player = (__bridge AVAudioPlayer *)(void *)(intptr_t)handle;
        player.numberOfLoops = count; // -1 = infinite, 0 = play once
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioSetVolume(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    // float is passed as int bits in localvar slot 2
    s32 bits = env->localvar_getInt(runtime->localvar, 2);
    float volume;
    memcpy(&volume, &bits, sizeof(float));
    if (handle) {
        AVAudioPlayer *player = (__bridge AVAudioPlayer *)(void *)(intptr_t)handle;
        player.volume = volume;
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioGetDuration(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    s64 duration = -1;
    if (handle) {
        AVAudioPlayer *player = (__bridge AVAudioPlayer *)(void *)(intptr_t)handle;
        duration = (s64)(player.duration * 1000000.0); // microseconds
    }
    env->push_long(runtime->stack, duration);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioGetTime(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    s64 time = 0;
    if (handle) {
        AVAudioPlayer *player = (__bridge AVAudioPlayer *)(void *)(intptr_t)handle;
        time = (s64)(player.currentTime * 1000000.0); // microseconds
    }
    env->push_long(runtime->stack, time);
    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// MIDI — AVMIDIPlayer + gs_instruments.sf2
// ============================================================

static s32 n_audioCreateMidiPlayer(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    Instance *arr = env->localvar_getRefer(runtime->localvar, 0);

    if (!arr) { env->push_long(runtime->stack, 0); return RUNTIME_STATUS_NORMAL; }

    ensureAudioSession();

    NSURL *sfURL = getSoundFontURL();
    if (!sfURL) {
        // AVMIDIPlayer with a nil soundBankURL throws an Obj-C exception inside
        // MIDIPlayerImpl::finishLoad rather than returning an NSError. Fail fast.
        env->push_long(runtime->stack, 0);
        return RUNTIME_STATUS_NORMAL;
    }

    s32 length = arr->arr_length;
    // SMF header is "MThd" + 6-byte length prefix + a 6-byte chunk = 14 bytes minimum.
    // Anything shorter cannot be a valid MIDI file and would also trip the exception.
    if (length < 14) {
        env->push_long(runtime->stack, 0);
        return RUNTIME_STATUS_NORMAL;
    }
    NSData *data = [NSData dataWithBytes:arr->arr_body length:length];

    AVMIDIPlayer *player = nil;
    NSError *error = nil;
    @try {
        player = [[AVMIDIPlayer alloc] initWithData:data
                                       soundBankURL:sfURL
                                              error:&error];
    } @catch (NSException *e) {
        // AVMIDIPlayer raises NSException (not NSError) on malformed MIDI data —
        // e.g. games that pass custom/non-SMF streams. Swallow and report failure
        // so the Java caller can handle MediaException gracefully.
        printf("[J2ME Audio] AVMIDIPlayer init threw %s: %s\n",
               [[e name] UTF8String] ?: "(no name)",
               [[e reason] UTF8String] ?: "(no reason)");
        env->push_long(runtime->stack, 0);
        return RUNTIME_STATUS_NORMAL;
    }
    if (error || !player) {
        printf("[J2ME Audio] AVMIDIPlayer init error: %s\n",
               error ? [[error localizedDescription] UTF8String] : "nil");
        env->push_long(runtime->stack, 0);
        return RUNTIME_STATUS_NORMAL;
    }

    [player prepareToPlay];
    CFRetain((__bridge CFTypeRef)player);
    track_midi_player(player);
    set_player_heap_bytes(player, length);
    audio_heap_add(length);
    env->push_long(runtime->stack, (s64)(intptr_t)(__bridge void *)player);
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioMidiStart(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    if (handle) {
        AVMIDIPlayer *player = (__bridge AVMIDIPlayer *)(void *)(intptr_t)handle;
        [player play:nil];
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioMidiStop(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    if (handle) {
        AVMIDIPlayer *player = (__bridge AVMIDIPlayer *)(void *)(intptr_t)handle;
        [player stop];
    }
    return RUNTIME_STATUS_NORMAL;
}

static s32 n_audioMidiClose(Runtime *runtime, JClass *clazz) {
    JniEnv *env = runtime->jnienv;
    s64 handle = env->localvar_getLong_2slot(runtime->localvar, 0);
    if (handle) {
        AVMIDIPlayer *player = (__bridge AVMIDIPlayer *)(void *)(intptr_t)handle;
        if (claim_midi_player(player)) {
            [player stop];
            audio_heap_sub(take_player_heap_bytes(player));
            CFRelease((__bridge CFTypeRef)player);
        }
        // else: j2me_audio_stop_all already took ownership; do nothing.
    }
    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// Tone — convenience (not used directly, Java uses ToneManager)
// ============================================================

static s32 n_audioPlayTone(Runtime *runtime, JClass *clazz) {
    // This is a fallback — normally ToneManager handles playTone via TonePlayer
    JniEnv *env = runtime->jnienv;
    s32 note = env->localvar_getInt(runtime->localvar, 0);
    s32 duration = env->localvar_getInt(runtime->localvar, 1);
    s32 volume = env->localvar_getInt(runtime->localvar, 2);
    printf("[J2ME Audio] playTone: note=%d duration=%d volume=%d\n", note, duration, volume);
    // Tone is handled by Java ToneManager → ToneSequence → MIDI → AVMIDIPlayer
    return RUNTIME_STATUS_NORMAL;
}

// ============================================================
// Native method table
// ============================================================

#define CLS "javax/microedition/lcdui/NativeBridge"

static java_native_method j2me_audio_methods[] = {
    // WAV/MP3
    {CLS, "audioCreatePlayer",     "([B)J",   n_audioCreatePlayer},
    {CLS, "audioStart",            "(J)V",    n_audioStart},
    {CLS, "audioStop",             "(J)V",    n_audioStop},
    {CLS, "audioClose",            "(J)V",    n_audioClose},
    {CLS, "audioSetLoop",          "(JI)V",   n_audioSetLoop},
    {CLS, "audioSetVolume",        "(JF)V",   n_audioSetVolume},
    {CLS, "audioGetDuration",      "(J)J",    n_audioGetDuration},
    {CLS, "audioGetTime",          "(J)J",    n_audioGetTime},
    // MIDI
    {CLS, "audioCreateMidiPlayer", "([B)J",   n_audioCreateMidiPlayer},
    {CLS, "audioMidiStart",        "(J)V",    n_audioMidiStart},
    {CLS, "audioMidiStop",         "(J)V",    n_audioMidiStop},
    {CLS, "audioMidiClose",        "(J)V",    n_audioMidiClose},
    // Tone
    {CLS, "audioPlayTone",         "(III)V",  n_audioPlayTone},
};

#undef CLS

void j2me_audio_reg_natives(MiniJVM *jvm) {
    native_reg_lib(jvm, j2me_audio_methods,
                   sizeof(j2me_audio_methods) / sizeof(java_native_method));
    printf("[J2ME Audio] Registered %lu native methods\n",
           sizeof(j2me_audio_methods) / sizeof(java_native_method));
}
