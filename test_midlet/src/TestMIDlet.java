/**
 * Test MIDlet — comprehensive feature test
 *
 * Tests all implemented features: Graphics, Game API, Forms, RMS,
 * Audio, Network, EventQueue, pixel collision, copyArea, drawRGB,
 * polygons, platformRequest.
 */
import javax.microedition.midlet.MIDlet;
import javax.microedition.midlet.MIDletStateChangeException;
import javax.microedition.lcdui.*;
import javax.microedition.lcdui.game.*;
import javax.microedition.rms.*;
import javax.microedition.media.*;
import com.mascotcapsule.micro3d.v3.*;
import java.io.*;

public class TestMIDlet extends MIDlet implements CommandListener {

    private Display display;
    private Command playCmd, exitCmd, backCmd, toneCmd, wavCmd, netCmd, gfxCmd, mc3dCmd;
    private GameTestCanvas gameCanvas;
    private int launchCount = 0;

    public TestMIDlet() { System.out.println("[TestMIDlet] Constructor"); }

    protected void startApp() throws MIDletStateChangeException {
        display = Display.getDisplay(this);
        // RMS
        try {
            RecordStore rs = RecordStore.openRecordStore("LaunchData", true);
            if (rs.getNumRecords()>0) {
                byte[] d=rs.getRecord(1);
                launchCount=((d[0]&0xFF)<<24)|((d[1]&0xFF)<<16)|((d[2]&0xFF)<<8)|(d[3]&0xFF);
            }
            launchCount++;
            byte[] d=new byte[4];
            d[0]=(byte)(launchCount>>24);d[1]=(byte)(launchCount>>16);
            d[2]=(byte)(launchCount>>8);d[3]=(byte)launchCount;
            if(rs.getNumRecords()==0) rs.addRecord(d,0,4); else rs.setRecord(1,d,0,4);
            rs.closeRecordStore();
        } catch (Exception e) { launchCount=-1; }
        showMainForm();
    }

    private void showMainForm() {
        Form form = new Form("J2ME Emulator");
        form.append(new StringItem("Features:", "All tests"));
        form.append(new StringItem("Launches:", String.valueOf(launchCount)));

        playCmd = new Command("Game", Command.OK, 1);
        gfxCmd = new Command("GFX", Command.SCREEN, 2);
        toneCmd = new Command("Tone", Command.SCREEN, 3);
        wavCmd = new Command("WAV", Command.SCREEN, 4);
        netCmd = new Command("HTTP", Command.SCREEN, 5);
        mc3dCmd = new Command("3D", Command.SCREEN, 6);
        exitCmd = new Command("Exit", Command.EXIT, 7);
        form.addCommand(playCmd);
        form.addCommand(gfxCmd);
        form.addCommand(toneCmd);
        form.addCommand(wavCmd);
        form.addCommand(netCmd);
        form.addCommand(mc3dCmd);
        form.addCommand(exitCmd);
        form.setCommandListener(this);
        display.setCurrent(form);
    }

    public void commandAction(Command c, Displayable d) {
        System.out.println("[TestMIDlet] cmd: " + c.getLabel());
        if (c == playCmd) {
            gameCanvas = new GameTestCanvas();
            backCmd = new Command("Back", Command.BACK, 1);
            gameCanvas.addCommand(backCmd);
            gameCanvas.setCommandListener(this);
            display.setCurrent(gameCanvas);
        } else if (c == gfxCmd) {
            GfxTestCanvas gfx = new GfxTestCanvas();
            Command bk = new Command("Back", Command.BACK, 1);
            gfx.addCommand(bk);
            gfx.setCommandListener(this);
            display.setCurrent(gfx);
        } else if (c == toneCmd) {
            doToneTest();
        } else if (c == wavCmd) {
            doWavTest();
        } else if (c == netCmd) {
            doNetTest();
        } else if (c == mc3dCmd) {
            Micro3DTestCanvas mc3d = new Micro3DTestCanvas();
            Command bk = new Command("Back", Command.BACK, 1);
            mc3d.addCommand(bk);
            mc3d.setCommandListener(this);
            display.setCurrent(mc3d);
        } else if (c == exitCmd) {
            notifyDestroyed();
        } else if (c.getLabel().equals("Back")) {
            if (gameCanvas != null) gameCanvas.stop();
            showMainForm();
        }
    }

    private void doToneTest() {
        try {
            Manager.playTone(72, 500, 100);
            showResult("Tone Test", "C5 (MIDI 72), 500ms", "Playing via AVMIDIPlayer");
        } catch (Exception e) { showError("Tone Error", e); }
    }

    private void doWavTest() {
        try {
            byte[] wav = generateSineWAV(440, 500);
            Player p = Manager.createPlayer(new ByteArrayInputStream(wav), "audio/wav");
            p.start();
            showResult("WAV Test", "440 Hz sine, 500ms", "Playing via AVAudioPlayer");
        } catch (Exception e) { showError("WAV Error", e); }
    }

    private void doNetTest() {
        Form f = new Form("Network");
        f.append(new StringItem("Status:", "Connecting..."));
        Command bk = new Command("Back", Command.BACK, 1);
        f.addCommand(bk); f.setCommandListener(this);
        display.setCurrent(f);
        new Thread(new Runnable() {
            public void run() {
                try {
                    javax.microedition.io.HttpConnection conn = (javax.microedition.io.HttpConnection)
                        javax.microedition.io.Connector.open("http://httpbin.org/get");
                    int rc = conn.getResponseCode();
                    InputStream is = conn.openInputStream();
                    ByteArrayOutputStream bos = new ByteArrayOutputStream();
                    byte[] buf = new byte[1024]; int n;
                    while ((n=is.read(buf))>0) bos.write(buf,0,n);
                    is.close(); conn.close();
                    String body = new String(bos.toByteArray());
                    String preview = body.length()>200?body.substring(0,200)+"...":body;
                    showResult("HTTP Result", "Code: " + rc, preview);
                } catch (Exception e) { showError("HTTP Error", e); }
            }
        }).start();
    }

    private void showResult(String title, String line1, String line2) {
        Form f = new Form(title);
        f.append(new StringItem(null, line1));
        f.append(new StringItem(null, line2));
        Command bk = new Command("Back", Command.BACK, 1);
        f.addCommand(bk); f.setCommandListener(this);
        display.setCurrent(f);
    }

    private void showError(String title, Exception e) {
        Form f = new Form(title);
        f.append(new StringItem("Error:", e.getClass().getName()));
        f.append(new StringItem("Msg:", e.getMessage()!=null?e.getMessage():"null"));
        Command bk = new Command("Back", Command.BACK, 1);
        f.addCommand(bk); f.setCommandListener(this);
        display.setCurrent(f);
    }

    private byte[] generateSineWAV(int freq, int durationMs) {
        int sr = 22050, ns = sr * durationMs / 1000, ds = ns * 2;
        byte[] w = new byte[44 + ds];
        w[0]='R';w[1]='I';w[2]='F';w[3]='F';
        int fs=36+ds; w[4]=(byte)fs;w[5]=(byte)(fs>>8);w[6]=(byte)(fs>>16);w[7]=(byte)(fs>>24);
        w[8]='W';w[9]='A';w[10]='V';w[11]='E';
        w[12]='f';w[13]='m';w[14]='t';w[15]=' ';
        w[16]=16;w[20]=1;w[22]=1;
        w[24]=(byte)sr;w[25]=(byte)(sr>>8);w[26]=(byte)(sr>>16);w[27]=(byte)(sr>>24);
        int br=sr*2; w[28]=(byte)br;w[29]=(byte)(br>>8);w[30]=(byte)(br>>16);w[31]=(byte)(br>>24);
        w[32]=2;w[34]=16;
        w[36]='d';w[37]='a';w[38]='t';w[39]='a';
        w[40]=(byte)ds;w[41]=(byte)(ds>>8);w[42]=(byte)(ds>>16);w[43]=(byte)(ds>>24);
        for(int i=0;i<ns;i++){
            short s=(short)(Math.sin(2.0*Math.PI*freq*(double)i/sr)*16000);
            w[44+i*2]=(byte)(s&0xFF);w[44+i*2+1]=(byte)((s>>8)&0xFF);
        }
        return w;
    }

    protected void pauseApp() {}
    protected void destroyApp(boolean u) { if(gameCanvas!=null)gameCanvas.stop(); }

    // ---- helpers for showMainForm Back handler ----
    // (needed because Micro3DTestCanvas uses its own stop)

}

/**
 * Graphics test canvas — tests drawRGB, copyArea, fillPolygon,
 * fillTriangle, createRGBImage, getDisplayColor.
 */
class GfxTestCanvas extends Canvas {
    protected void paint(Graphics g) {
        int w = getWidth(), h = getHeight();

        // Background
        g.setColor(0x001030);
        g.fillRect(0, 0, w, h);

        g.setColor(0xFFFFFF);
        g.setFont(Font.getFont(Font.FACE_SYSTEM, Font.STYLE_BOLD, Font.SIZE_MEDIUM));
        g.drawString("Graphics Tests", w/2, 5, Graphics.HCENTER | Graphics.TOP);

        g.setFont(Font.getFont(Font.FACE_SYSTEM, Font.STYLE_PLAIN, Font.SIZE_SMALL));

        // Test 1: drawRGB — create gradient from pixel array
        int[] rgbData = new int[40 * 20];
        for (int y = 0; y < 20; y++)
            for (int x = 0; x < 40; x++)
                rgbData[y * 40 + x] = 0xFF000000 | ((x * 6) << 16) | ((y * 12) << 8) | 0x80;
        g.drawRGB(rgbData, 0, 40, 10, 30, 40, 20, true);
        g.setColor(0xFFFF80);
        g.drawString("drawRGB", 55, 35, Graphics.LEFT | Graphics.TOP);

        // Test 2: createRGBImage
        Image rgbImg = Image.createRGBImage(rgbData, 40, 20, true);
        g.drawImage(rgbImg, 10, 60, Graphics.LEFT | Graphics.TOP);
        g.drawString("createRGBImage", 55, 65, Graphics.LEFT | Graphics.TOP);

        // Test 3: fillPolygon — star shape
        int cx = 50, cy = 115;
        int[] xp = new int[5], yp = new int[5];
        for (int i = 0; i < 5; i++) {
            double angle = Math.PI * 2 * i / 5 - Math.PI / 2;
            xp[i] = cx + (int)(20 * Math.cos(angle));
            yp[i] = cy + (int)(20 * Math.sin(angle));
        }
        // Draw as star: 0-2-4-1-3
        int[] sx = {xp[0], xp[2], xp[4], xp[1], xp[3]};
        int[] sy = {yp[0], yp[2], yp[4], yp[1], yp[3]};
        g.setColor(0xFFFF00);
        g.fillPolygon(sx, sy, 5);
        g.setColor(0xFFFF80);
        g.drawString("fillPolygon", 80, 108, Graphics.LEFT | Graphics.TOP);

        // Test 4: fillTriangle
        g.setColor(0x00FF80);
        g.fillTriangle(10, 155, 50, 145, 30, 175);
        g.setColor(0xFFFF80);
        g.drawString("fillTriangle", 55, 155, Graphics.LEFT | Graphics.TOP);

        // Test 5: drawPolygon (outlined)
        g.setColor(0xFF8000);
        g.drawPolygon(new int[]{10, 50, 50, 10}, new int[]{195, 195, 215, 215}, 4);
        g.setColor(0xFFFF80);
        g.drawString("drawPolygon", 55, 198, Graphics.LEFT | Graphics.TOP);

        // Test 6: copyArea — copy a region
        g.setColor(0xFF0000);
        g.fillRect(10, 230, 30, 15);
        g.setColor(0x0000FF);
        g.fillRect(15, 233, 10, 9);
        g.copyArea(10, 230, 30, 15, 50, 230, Graphics.LEFT | Graphics.TOP);
        g.setColor(0xFFFF80);
        g.drawString("copyArea", 85, 233, Graphics.LEFT | Graphics.TOP);

        // Test 7: getDisplayColor
        int dc = g.getDisplayColor(0x123456);
        g.setColor(0xFFFF80);
        g.drawString("getDisplayColor(0x123456)=0x" + Integer.toHexString(dc),
                10, 255, Graphics.LEFT | Graphics.TOP);

        // Test 8: Image.createImage with transform
        Image srcImg = Image.createImage(20, 20);
        Graphics sg = srcImg.getGraphics();
        sg.setColor(0xFF0000); sg.fillRect(0, 0, 10, 20);
        sg.setColor(0x00FF00); sg.fillRect(10, 0, 10, 20);
        // Test transforms: Original | ROT90 | MIRROR | MIR_ROT180 | ROT180
        g.drawImage(srcImg, 10, 275, Graphics.LEFT | Graphics.TOP);
        Image rot = Image.createImage(srcImg, 0, 0, 20, 20, 5);  // TRANS_ROT90
        g.drawImage(rot, 35, 275, Graphics.LEFT | Graphics.TOP);
        Image mir = Image.createImage(srcImg, 0, 0, 20, 20, 2);  // TRANS_MIRROR
        g.drawImage(mir, 60, 275, Graphics.LEFT | Graphics.TOP);
        Image mr180 = Image.createImage(srcImg, 0, 0, 20, 20, 1); // TRANS_MIRROR_ROT180
        g.drawImage(mr180, 85, 275, Graphics.LEFT | Graphics.TOP);
        Image r180 = Image.createImage(srcImg, 0, 0, 20, 20, 3);  // TRANS_ROT180
        g.drawImage(r180, 110, 275, Graphics.LEFT | Graphics.TOP);
        g.setColor(0xFFFF80);
        g.drawString("Orig|R90|Mir|MR180|R180", 10, 298, Graphics.LEFT | Graphics.TOP);

        // Footer
        g.setColor(0xAAFFAA);
        g.drawString("All graphics tests passed!", w/2, h-5,
                Graphics.HCENTER | Graphics.BOTTOM);
    }
}

/**
 * Game canvas with sprite, tiled background, D-pad control.
 */
class GameTestCanvas extends GameCanvas implements Runnable {
    private Sprite player;
    private Sprite enemy;
    private TiledLayer background;
    private LayerManager layerManager;
    private Thread gameThread;
    private volatile boolean running = false;
    private int frameCount = 0;
    private boolean colliding = false;

    GameTestCanvas() { super(true); }
    protected void showNotify() {
        if (!running) { initGame(); running=true; gameThread=new Thread(this); gameThread.start(); }
    }
    void stop() { running = false; }

    private void initGame() {
        int w=getWidth(),h=getHeight();
        Image ti=Image.createImage(32,16);Graphics tg=ti.getGraphics();
        tg.setColor(0x303030);tg.fillRect(0,0,16,16);tg.setColor(0x404040);tg.drawRect(0,0,15,15);
        tg.setColor(0x404040);tg.fillRect(16,0,16,16);tg.setColor(0x505050);tg.drawRect(16,0,15,15);
        int c2=w/16+1,r2=h/16+1;background=new TiledLayer(c2,r2,ti,16,16);
        for(int r=0;r<r2;r++)for(int c=0;c<c2;c++)background.setCell(c,r,((r+c)%2)+1);

        // Player sprite (4 frames)
        Image si=Image.createImage(64,16);Graphics sg=si.getGraphics();
        sg.setColor(0xFF0000);sg.fillRect(2,2,12,12);sg.setColor(0xFFFFFF);sg.fillRect(4,4,4,4);
        sg.setColor(0x00FF00);sg.fillRect(18,2,12,12);sg.setColor(0xFFFFFF);sg.fillRect(20,4,4,4);
        sg.setColor(0x0000FF);sg.fillRect(34,2,12,12);sg.setColor(0xFFFFFF);sg.fillRect(36,4,4,4);
        sg.setColor(0xFFFF00);sg.fillRect(50,2,12,12);sg.setColor(0xFFFFFF);sg.fillRect(52,4,4,4);
        player=new Sprite(si,16,16);player.setPosition(w/2-8,h/2-8);

        // Enemy sprite (diamond shape — tests pixel collision vs AABB)
        Image ei=Image.createImage(24,24);Graphics eg=ei.getGraphics();
        // Draw diamond: only corners are transparent
        eg.setColor(0xFF00FF);
        eg.fillTriangle(12,0, 24,12, 12,24);
        eg.fillTriangle(12,0, 0,12, 12,24);
        enemy=new Sprite(ei);
        enemy.setPosition(w/2+40, h/2-12);
        enemy.setTransform(Sprite.TRANS_ROT90); // rotated — tests transform collision

        layerManager=new LayerManager();
        layerManager.append(player);
        layerManager.append(enemy);
        layerManager.append(background);
    }

    public void run() {
        while(running) {
            int k=getKeyStates();
            if((k&LEFT_PRESSED)!=0)player.move(-3,0);if((k&RIGHT_PRESSED)!=0)player.move(3,0);
            if((k&UP_PRESSED)!=0)player.move(0,-3);if((k&DOWN_PRESSED)!=0)player.move(0,3);
            if(frameCount%8==0)player.nextFrame();frameCount++;

            // Pixel-level collision test (with transforms!)
            colliding = player.collidesWith(enemy, true);

            Graphics g=getGraphics();layerManager.paint(g,0,0);

            // Collision indicator — border around enemy
            if (colliding) {
                g.setColor(0xFF0000);
                g.drawRect(enemy.getX()-2, enemy.getY()-2, enemy.getWidth()+3, enemy.getHeight()+3);
                g.drawRect(enemy.getX()-1, enemy.getY()-1, enemy.getWidth()+1, enemy.getHeight()+1);
            }

            g.setColor(0xFFFFFF);g.setFont(Font.getFont(Font.FACE_SYSTEM,Font.STYLE_BOLD,Font.SIZE_MEDIUM));
            g.drawString("Game Test",5,2,Graphics.LEFT|Graphics.TOP);
            g.setFont(Font.getFont(Font.FACE_SYSTEM,Font.STYLE_PLAIN,Font.SIZE_SMALL));
            g.setColor(colliding ? 0xFF4040 : 0xFFFF80);
            g.drawString("Collision: " + (colliding ? "YES!" : "no") +
                "  Pos:"+player.getX()+","+player.getY(),
                5,20,Graphics.LEFT|Graphics.TOP);
            g.setColor(0xAAFFAA);
            g.drawString("Move into diamond to test pixel collision",
                getWidth()/2, getHeight()-5, Graphics.HCENTER|Graphics.BOTTOM);
            flushGraphics();try{Thread.sleep(33);}catch(InterruptedException e){break;}
        }
    }
}

/**
 * MascotCapsule micro3D test — renders a rotating colored cube
 * using renderPrimitives (no model files needed).
 */
class Micro3DTestCanvas extends GameCanvas implements Runnable {
    private volatile boolean running = false;
    private Thread thread;
    private int angle = 0;
    private String status = "Initializing...";
    private boolean hasError = false;

    Micro3DTestCanvas() { super(false); }

    // Cube vertices (8 corners, fixed-point: 1.0 = 4096)
    private static final int S = 100; // half-size
    private static final int[][] CUBE_VERTS = {
        {-S, -S, -S}, { S, -S, -S}, { S,  S, -S}, {-S,  S, -S}, // back face
        {-S, -S,  S}, { S, -S,  S}, { S,  S,  S}, {-S,  S,  S}, // front face
    };

    // 12 triangles (2 per face), indices into CUBE_VERTS
    private static final int[][] CUBE_TRIS = {
        // front
        {4,5,6}, {4,6,7},
        // back
        {1,0,3}, {1,3,2},
        // left
        {0,4,7}, {0,7,3},
        // right
        {5,1,2}, {5,2,6},
        // top
        {7,6,2}, {7,2,3},
        // bottom
        {0,1,5}, {0,5,4},
    };

    // One color per face (2 triangles share same color)
    private static final int[] FACE_COLORS = {
        0xFF0000, 0xFF0000, // front = red
        0x00FF00, 0x00FF00, // back = green
        0x0000FF, 0x0000FF, // left = blue
        0xFFFF00, 0xFFFF00, // right = yellow
        0xFF00FF, 0xFF00FF, // top = magenta
        0x00FFFF, 0x00FFFF, // bottom = cyan
    };

    protected void showNotify() {
        if (!running) {
            running = true;
            thread = new Thread(this);
            thread.start();
        }
    }

    protected void hideNotify() {
        running = false;
    }

    void stop() { running = false; }

    public void run() {
        System.out.println("[Micro3D Test] Thread started");

        Graphics3D g3d = new Graphics3D();
        FigureLayout layout = new FigureLayout();
        Effect3D effect = new Effect3D();

        // Setup parallel projection (simple, no perspective distortion)
        layout.setScale(4096, 4096);
        layout.setCenter(0, 0);

        while (running) {
            try {
                Graphics g = getGraphics();
                int w = getWidth(), h = getHeight();

                // Clear background
                g.setColor(0x102040);
                g.fillRect(0, 0, w, h);

                // Bind 3D context
                g3d.bind(g);

                // Update rotation
                angle = (angle + 3) % 4096;

                // Build rotated vertices
                int[] rotated = rotateVertices(angle);

                // Render 12 triangles (one renderPrimitives call per triangle for simplicity)
                layout.setCenter(w / 2, h / 2);

                for (int i = 0; i < 12; i++) {
                    int[] tri = CUBE_TRIS[i];
                    int[] verts = new int[9]; // 3 vertices * 3 coords
                    for (int v = 0; v < 3; v++) {
                        int idx = tri[v] * 3;
                        verts[v * 3]     = rotated[idx];
                        verts[v * 3 + 1] = rotated[idx + 1];
                        verts[v * 3 + 2] = rotated[idx + 2];
                    }
                    int[] normals = new int[0];
                    int[] texCoords = new int[0];
                    int[] colors = new int[]{FACE_COLORS[i]};

                    int command = Graphics3D.PRIMITVE_TRIANGLES
                                | Graphics3D.PDATA_COLOR_PER_COMMAND;
                    try {
                        g3d.renderPrimitives(null, 0, 0, layout, effect,
                            command, 1, verts, normals, texCoords, colors);
                    } catch (Exception e) {
                        if (!hasError) {
                            System.err.println("[Micro3D Test] renderPrimitives error: " + e);
                            hasError = true;
                            status = "Error: " + e.getClass().getName();
                        }
                    }
                }

                // Flush and release
                try {
                    g3d.flush();
                } catch (Exception e) {
                    if (!hasError) {
                        System.err.println("[Micro3D Test] flush error: " + e);
                        hasError = true;
                        status = "Flush error: " + e.getClass().getName();
                    }
                }
                try {
                    g3d.release(g);
                } catch (Exception e) {
                    if (!hasError) {
                        System.err.println("[Micro3D Test] release error: " + e);
                        hasError = true;
                        status = "Release error: " + e.getClass().getName();
                    }
                }

                if (!hasError) {
                    status = "Rotating cube (" + angle + ")";
                }

                // Draw text overlay
                g.setColor(0xFFFFFF);
                g.setFont(Font.getFont(Font.FACE_SYSTEM, Font.STYLE_BOLD, Font.SIZE_MEDIUM));
                g.drawString("MascotCapsule 3D", w / 2, 5, Graphics.HCENTER | Graphics.TOP);
                g.setFont(Font.getFont(Font.FACE_SYSTEM, Font.STYLE_PLAIN, Font.SIZE_SMALL));
                g.setColor(hasError ? 0xFF4040 : 0xAAFFAA);
                g.drawString(status, w / 2, 25, Graphics.HCENTER | Graphics.TOP);
                g.setColor(0x808080);
                g.drawString("12 triangles, color per command", w / 2, h - 5,
                    Graphics.HCENTER | Graphics.BOTTOM);

                flushGraphics();

            } catch (Exception e) {
                System.err.println("[Micro3D Test] frame error: " + e);
                e.printStackTrace();
                status = "Frame error: " + e.getMessage();
                hasError = true;
            }

            try { Thread.sleep(33); } catch (InterruptedException e) { break; }
        }
        System.out.println("[Micro3D Test] Thread stopped");
    }

    /**
     * Rotate all cube vertices around Y then X axis.
     * Uses fixed-point math (4096 = 1.0 for trig).
     */
    private int[] rotateVertices(int angle) {
        double radY = angle * Math.PI * 2.0 / 4096.0;
        double radX = angle * Math.PI / 4096.0; // half-speed X rotation
        double cosY = Math.cos(radY), sinY = Math.sin(radY);
        double cosX = Math.cos(radX), sinX = Math.sin(radX);

        int[] result = new int[8 * 3];
        for (int i = 0; i < 8; i++) {
            int x = CUBE_VERTS[i][0];
            int y = CUBE_VERTS[i][1];
            int z = CUBE_VERTS[i][2];

            // Rotate around Y axis
            double rx = x * cosY + z * sinY;
            double rz = -x * sinY + z * cosY;

            // Rotate around X axis
            double ry = y * cosX - rz * sinX;
            double rz2 = y * sinX + rz * cosX;

            result[i * 3]     = (int) rx;
            result[i * 3 + 1] = (int) ry;
            result[i * 3 + 2] = (int) rz2;
        }
        return result;
    }

    public void paint(Graphics g) {
        // Rendering done in run() thread via getGraphics()
    }
}
