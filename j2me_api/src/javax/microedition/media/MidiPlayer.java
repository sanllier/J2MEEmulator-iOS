package javax.microedition.media;

import javax.microedition.lcdui.NativeBridge;

/**
 * Player for MIDI via native AVMIDIPlayer + gs_instruments.sf2.
 * Analogous to J2ME-Loader's MidiPlayer wrapping MidiDriver.
 */
public class MidiPlayer extends BasePlayer {
    private long nativeHandle;
    private byte[] midiData;

    public MidiPlayer(byte[] data) {
        this.midiData = data;
    }

    protected void doRealize() throws MediaException {
        if (midiData != null) {
            nativeHandle = NativeBridge.audioCreateMidiPlayer(midiData);
            if (nativeHandle == 0) throw new MediaException("Failed to create MIDI player");
        }
    }

    protected void doStart() throws MediaException {
        if (nativeHandle != 0) NativeBridge.audioMidiStart(nativeHandle);
    }

    protected void doStop() throws MediaException {
        if (nativeHandle != 0) NativeBridge.audioMidiStop(nativeHandle);
    }

    protected void doClose() {
        if (nativeHandle != 0) {
            NativeBridge.audioMidiClose(nativeHandle);
            nativeHandle = 0;
        }
        midiData = null;
    }

    // Safety net for misbehaving MIDlets that never close their players.
    // miniJVM's GC is infrequent so this fires late, but it still bounds
    // the AVMIDIPlayer + SoundFont retention to a single GC cycle past
    // last-use rather than leaking until j2me_audio_stop_all on shutdown.
    @Override
    protected void finalize() throws Throwable {
        try {
            if (nativeHandle != 0) {
                NativeBridge.audioMidiClose(nativeHandle);
                nativeHandle = 0;
            }
        } finally {
            super.finalize();
        }
    }
}
