package javax.microedition.io.impl;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.URL;

import javax.microedition.io.HttpsConnection;
import javax.microedition.io.SecurityInfo;
import javax.microedition.pki.Certificate;

/**
 * MIDP HttpConnection / HttpsConnection on top of java.net.HttpURLConnection.
 * Implements HttpsConnection so a single class covers both schemes — the
 * underlying URLConnection picks the right protocol handler from the URL.
 */
public class HttpConnectionImpl implements HttpsConnection {

    private final String urlString;
    private final URL parsedUrl;
    private final HttpURLConnection conn;
    private final boolean https;

    private boolean connected;
    private InputStream cachedInput;
    private OutputStream cachedOutput;

    public HttpConnectionImpl(String url, int mode, boolean timeouts) throws IOException {
        this.urlString = url;
        try {
            this.parsedUrl = new URL(url);
        } catch (MalformedURLException e) {
            throw new IOException("Malformed URL: " + url);
        }
        this.https = "https".equalsIgnoreCase(parsedUrl.getProtocol());

        Object opened;
        try {
            opened = parsedUrl.openConnection();
        } catch (IOException e) {
            throw e;
        }
        if (!(opened instanceof HttpURLConnection)) {
            throw new IOException("Not an HTTP URL: " + url);
        }
        this.conn = (HttpURLConnection) opened;
        this.conn.setDoInput(true);
        // doOutput is enabled lazily on openOutputStream — enabling it eagerly
        // would force every request into POST.
    }

    private void ensureConnected() throws IOException {
        if (!connected) {
            conn.connect();
            connected = true;
        }
    }

    public String getURL() { return urlString; }
    public String getProtocol() { return parsedUrl.getProtocol(); }
    public String getHost() { return parsedUrl.getHost(); }
    public String getFile() { return parsedUrl.getFile(); }
    public String getRef() { return parsedUrl.getRef(); }
    public String getQuery() { return parsedUrl.getQuery(); }

    @Override
    public int getPort() {
        int p = parsedUrl.getPort();
        if (p != -1) return p;
        return https ? 443 : 80;
    }

    public String getRequestMethod() { return conn.getRequestMethod(); }

    public void setRequestMethod(String method) throws IOException {
        if (connected) throw new IOException("connection already open");
        try {
            conn.setRequestMethod(method);
        } catch (java.net.ProtocolException e) {
            throw new IOException(e.getMessage());
        }
        if (POST.equals(method) || "PUT".equals(method)) {
            conn.setDoOutput(true);
        }
    }

    public String getRequestProperty(String key) {
        return conn.getRequestProperty(key);
    }

    public void setRequestProperty(String key, String value) throws IOException {
        if (connected) throw new IOException("connection already open");
        conn.setRequestProperty(key, value);
    }

    public int getResponseCode() throws IOException {
        ensureConnected();
        return conn.getResponseCode();
    }

    public String getResponseMessage() throws IOException {
        ensureConnected();
        return conn.getResponseMessage();
    }

    public long getExpiration() throws IOException {
        ensureConnected();
        return conn.getExpiration();
    }

    public long getDate() throws IOException {
        ensureConnected();
        return conn.getDate();
    }

    public long getLastModified() throws IOException {
        ensureConnected();
        return conn.getLastModified();
    }

    public String getHeaderField(String name) throws IOException {
        ensureConnected();
        return conn.getHeaderField(name);
    }

    public int getHeaderFieldInt(String name, int def) throws IOException {
        ensureConnected();
        return conn.getHeaderFieldInt(name, def);
    }

    public long getHeaderFieldDate(String name, long def) throws IOException {
        ensureConnected();
        return conn.getHeaderFieldDate(name, def);
    }

    public String getHeaderField(int n) throws IOException {
        ensureConnected();
        return conn.getHeaderField(n);
    }

    public String getHeaderFieldKey(int n) throws IOException {
        ensureConnected();
        return conn.getHeaderFieldKey(n);
    }

    // ---- ContentConnection ----

    public String getType() {
        try { ensureConnected(); } catch (IOException ignored) {}
        return conn.getContentType();
    }

    public String getEncoding() {
        try { ensureConnected(); } catch (IOException ignored) {}
        return conn.getContentEncoding();
    }

    public long getLength() {
        try { ensureConnected(); } catch (IOException ignored) {}
        return conn.getContentLength();
    }

    // ---- Stream/Input/OutputConnection ----

    public InputStream openInputStream() throws IOException {
        ensureConnected();
        if (cachedInput == null) cachedInput = conn.getInputStream();
        return cachedInput;
    }

    public DataInputStream openDataInputStream() throws IOException {
        return new DataInputStream(openInputStream());
    }

    public OutputStream openOutputStream() throws IOException {
        if (connected) throw new IOException("connection already open");
        conn.setDoOutput(true);
        if (cachedOutput == null) cachedOutput = conn.getOutputStream();
        return cachedOutput;
    }

    public DataOutputStream openDataOutputStream() throws IOException {
        return new DataOutputStream(openOutputStream());
    }

    public void close() throws IOException {
        try { if (cachedInput != null) cachedInput.close(); } catch (IOException ignored) {}
        try { if (cachedOutput != null) cachedOutput.close(); } catch (IOException ignored) {}
        conn.disconnect();
    }

    // ---- HttpsConnection ----

    public SecurityInfo getSecurityInfo() throws IOException {
        if (!https) throw new IOException("not an https connection");
        ensureConnected();
        // Detailed TLS metadata would require javax.net.ssl.HttpsURLConnection,
        // which miniJVM's bundled URL handler does not expose. Report a minimal
        // SecurityInfo so callers that just check getProtocolName() keep working.
        return new MinimalSecurityInfo();
    }

    private static final class MinimalSecurityInfo implements SecurityInfo {
        public Certificate getServerCertificate() { return null; }
        public String getProtocolVersion() { return "TLS"; }
        public String getProtocolName() { return "TLS"; }
        public String getCipherSuite() { return "UNKNOWN"; }
    }
}
