package javax.microedition.io;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import javax.microedition.io.file.impl.FileConnectionImpl;
import javax.microedition.io.impl.HttpConnectionImpl;
import javax.microedition.io.impl.ServerSocketConnectionImpl;
import javax.microedition.io.impl.SocketConnectionImpl;
import javax.microedition.io.impl.UDPDatagramConnectionImpl;

/**
 * MIDP Connector — parses the URL scheme and dispatches to a connection
 * implementation. The actual networking is provided by miniJVM's bundled
 * java.net.* stack; this class is just the protocol-handler dispatch table.
 */
public class Connector {

    public static final int READ = 1;
    public static final int WRITE = 2;
    public static final int READ_WRITE = 3;

    private Connector() { }

    public static Connection open(String name) throws IOException {
        return open(name, READ_WRITE, false);
    }

    public static Connection open(String name, int mode) throws IOException {
        return open(name, mode, false);
    }

    public static Connection open(String name, int mode, boolean timeouts) throws IOException {
        if (name == null) throw new IllegalArgumentException("name is null");
        int colon = name.indexOf(':');
        if (colon <= 0) throw new IllegalArgumentException("bad URL (no scheme): " + name);
        String scheme = name.substring(0, colon).toLowerCase();

        if (scheme.equals("http") || scheme.equals("https")) {
            return new HttpConnectionImpl(name, mode, timeouts);
        }
        if (scheme.equals("socket")) {
            return openSocket(name);
        }
        if (scheme.equals("serversocket")) {
            return new ServerSocketConnectionImpl(parsePort(stripScheme(name)));
        }
        if (scheme.equals("datagram")) {
            return openDatagram(name);
        }
        if (scheme.equals("file")) {
            return new FileConnectionImpl(name, mode);
        }
        throw new ConnectionNotFoundException("unsupported scheme: " + scheme);
    }

    public static DataInputStream openDataInputStream(String name) throws IOException {
        Connection c = open(name, READ);
        if (c instanceof InputConnection) {
            try {
                return ((InputConnection) c).openDataInputStream();
            } catch (IOException e) {
                try { c.close(); } catch (IOException ignored) {}
                throw e;
            }
        }
        try { c.close(); } catch (IOException ignored) {}
        throw new IOException("not an InputConnection: " + name);
    }

    public static DataOutputStream openDataOutputStream(String name) throws IOException {
        Connection c = open(name, WRITE);
        if (c instanceof OutputConnection) {
            try {
                return ((OutputConnection) c).openDataOutputStream();
            } catch (IOException e) {
                try { c.close(); } catch (IOException ignored) {}
                throw e;
            }
        }
        try { c.close(); } catch (IOException ignored) {}
        throw new IOException("not an OutputConnection: " + name);
    }

    public static InputStream openInputStream(String name) throws IOException {
        Connection c = open(name, READ);
        if (c instanceof InputConnection) {
            try {
                return ((InputConnection) c).openInputStream();
            } catch (IOException e) {
                try { c.close(); } catch (IOException ignored) {}
                throw e;
            }
        }
        try { c.close(); } catch (IOException ignored) {}
        throw new IOException("not an InputConnection: " + name);
    }

    public static OutputStream openOutputStream(String name) throws IOException {
        Connection c = open(name, WRITE);
        if (c instanceof OutputConnection) {
            try {
                return ((OutputConnection) c).openOutputStream();
            } catch (IOException e) {
                try { c.close(); } catch (IOException ignored) {}
                throw e;
            }
        }
        try { c.close(); } catch (IOException ignored) {}
        throw new IOException("not an OutputConnection: " + name);
    }

    // ---- scheme-specific URL parsing ----

    /** socket://host:port → client; socket://:port → server. */
    private static Connection openSocket(String url) throws IOException {
        String rest = stripScheme(url);  // "host:port" or ":port"
        if (rest.startsWith(":")) {
            return new ServerSocketConnectionImpl(parsePort(rest));
        }
        int colon = rest.lastIndexOf(':');
        if (colon <= 0) throw new IOException("bad socket URL (need host:port): " + url);
        String host = rest.substring(0, colon);
        int port;
        try {
            port = Integer.parseInt(rest.substring(colon + 1));
        } catch (NumberFormatException e) {
            throw new IOException("bad port: " + url);
        }
        return new SocketConnectionImpl(host, port);
    }

    /** datagram://host:port → client; datagram://:port → server; datagram:// → ephemeral. */
    private static Connection openDatagram(String url) throws IOException {
        String rest = stripScheme(url);
        if (rest.isEmpty()) {
            return new UDPDatagramConnectionImpl(null, -1);
        }
        if (rest.startsWith(":")) {
            return new UDPDatagramConnectionImpl(null, parsePort(rest));
        }
        int colon = rest.lastIndexOf(':');
        if (colon <= 0) throw new IOException("bad datagram URL: " + url);
        String host = rest.substring(0, colon);
        int port;
        try {
            port = Integer.parseInt(rest.substring(colon + 1));
        } catch (NumberFormatException e) {
            throw new IOException("bad port: " + url);
        }
        return new UDPDatagramConnectionImpl(host, port);
    }

    /** Strip "scheme://" prefix, return whatever follows (or empty). */
    private static String stripScheme(String url) {
        int p = url.indexOf("://");
        return p >= 0 ? url.substring(p + 3) : "";
    }

    /** Parse ":port" or "port" → int. */
    private static int parsePort(String s) throws IOException {
        if (s.startsWith(":")) s = s.substring(1);
        if (s.isEmpty()) return 0;
        // Strip trailing path if any: ":1234/foo" → "1234"
        int slash = s.indexOf('/');
        if (slash >= 0) s = s.substring(0, slash);
        try {
            return Integer.parseInt(s);
        } catch (NumberFormatException e) {
            throw new IOException("bad port: " + s);
        }
    }
}
