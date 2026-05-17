package javax.microedition.io.file.impl;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.RandomAccessFile;
import java.util.Enumeration;
import java.util.Vector;

import javax.microedition.io.Connector;
import javax.microedition.io.file.FileConnection;

/**
 * MIDP FileConnection on top of java.io.File. URL form:
 *   file:///absolute/path  → java.io.File("/absolute/path")
 *   file://host/path       → host is ignored, java.io.File("/path")
 *
 * No iOS-specific sandboxing is enforced here — the underlying open()
 * fails with IOException if the OS denies access. Apps should write under
 * the MIDlet's save root (system property "app.save.root") to stay legal.
 */
public class FileConnectionImpl implements FileConnection {

    private final String url;
    private File file;
    private final int mode;
    private boolean open = true;

    private InputStream cachedInput;
    private OutputStream cachedOutput;

    public FileConnectionImpl(String url, int mode) throws IOException {
        this.url = url;
        this.mode = mode;
        this.file = parsePath(url);
    }

    private static File parsePath(String url) throws IOException {
        if (!url.startsWith("file:")) throw new IOException("not a file:// URL: " + url);
        String rest = url.substring(5);
        // Strip leading // and optional host.
        if (rest.startsWith("//")) {
            rest = rest.substring(2);
            int slash = rest.indexOf('/');
            if (slash < 0) throw new IOException("missing path: " + url);
            // Drop host, keep path (starting with /).
            rest = rest.substring(slash);
        }
        return new File(rest);
    }

    public boolean isOpen() { return open; }

    public InputStream openInputStream() throws IOException {
        if ((mode & Connector.READ) == 0) throw new IOException("not opened for reading");
        if (cachedInput == null) cachedInput = new FileInputStream(file);
        return cachedInput;
    }

    public DataInputStream openDataInputStream() throws IOException {
        return new DataInputStream(openInputStream());
    }

    public OutputStream openOutputStream() throws IOException {
        if ((mode & Connector.WRITE) == 0) throw new IOException("not opened for writing");
        if (cachedOutput == null) cachedOutput = new FileOutputStream(file);
        return cachedOutput;
    }

    public DataOutputStream openDataOutputStream() throws IOException {
        return new DataOutputStream(openOutputStream());
    }

    public OutputStream openOutputStream(long byteOffset) throws IOException {
        if ((mode & Connector.WRITE) == 0) throw new IOException("not opened for writing");
        // RandomAccessFile is the standard way to start writing mid-file.
        final RandomAccessFile raf = new RandomAccessFile(file, "rw");
        raf.seek(byteOffset);
        OutputStream os = new OutputStream() {
            @Override public void write(int b) throws IOException { raf.write(b); }
            @Override public void write(byte[] b) throws IOException { raf.write(b); }
            @Override public void write(byte[] b, int off, int len) throws IOException { raf.write(b, off, len); }
            @Override public void close() throws IOException { raf.close(); }
        };
        cachedOutput = os;
        return os;
    }

    public long totalSize() {
        File root = file.isDirectory() ? file : file.getParentFile();
        return root != null ? root.getTotalSpace() : 0L;
    }

    public long availableSize() {
        File root = file.isDirectory() ? file : file.getParentFile();
        return root != null ? root.getFreeSpace() : 0L;
    }

    public long usedSize() {
        return totalSize() - availableSize();
    }

    public long directorySize(boolean includeSubDirs) throws IOException {
        if (!file.isDirectory()) throw new IOException("not a directory");
        return dirSize(file, includeSubDirs);
    }

    private static long dirSize(File dir, boolean recurse) {
        long total = 0;
        File[] kids = dir.listFiles();
        if (kids == null) return 0;
        for (File k : kids) {
            if (k.isDirectory()) {
                if (recurse) total += dirSize(k, true);
            } else {
                total += k.length();
            }
        }
        return total;
    }

    public long fileSize() throws IOException {
        if (!file.exists()) throw new IOException("does not exist");
        return file.length();
    }

    public boolean canRead()  { return file.canRead(); }
    public boolean canWrite() { return file.canWrite(); }
    public boolean isHidden() { return file.isHidden(); }

    public void setReadable(boolean readable) throws IOException {
        if (!file.setReadable(readable)) throw new IOException("setReadable failed");
    }

    public void setWritable(boolean writable) throws IOException {
        if (!file.setWritable(writable)) throw new IOException("setWritable failed");
    }

    public void setHidden(boolean hidden) throws IOException {
        // No portable cross-platform way; iOS treats dot-prefixed files as hidden.
        // No-op rather than throwing — matches conservative MIDP behaviour.
    }

    public Enumeration list() throws IOException {
        return list("*", false);
    }

    public Enumeration list(String filter, boolean includeHidden) throws IOException {
        if (!file.isDirectory()) throw new IOException("not a directory");
        String[] names = file.list();
        if (names == null) return new Vector().elements();
        // Simple glob filter — supports '*' wildcard.
        Vector<String> result = new Vector<String>();
        for (String n : names) {
            if (!includeHidden && n.startsWith(".")) continue;
            if (matchGlob(n, filter)) {
                File f = new File(file, n);
                result.add(f.isDirectory() ? n + "/" : n);
            }
        }
        return result.elements();
    }

    private static boolean matchGlob(String name, String pat) {
        if (pat == null || pat.equals("*") || pat.equals("*.*")) return true;
        // Trivial *prefix*suffix matcher — good enough for MIDP filters.
        int star = pat.indexOf('*');
        if (star < 0) return name.equals(pat);
        String prefix = pat.substring(0, star);
        String suffix = pat.substring(star + 1);
        return name.startsWith(prefix) && name.endsWith(suffix)
                && name.length() >= prefix.length() + suffix.length();
    }

    public void create() throws IOException {
        if (!file.createNewFile()) throw new IOException("create failed");
    }

    public void mkdir() throws IOException {
        if (!file.mkdir()) throw new IOException("mkdir failed");
    }

    public boolean exists() { return file.exists(); }
    public boolean isDirectory() { return file.isDirectory(); }

    public void delete() throws IOException {
        if (!file.delete()) throw new IOException("delete failed");
    }

    public void rename(String newName) throws IOException {
        File dst = new File(file.getParentFile(), newName);
        if (!file.renameTo(dst)) throw new IOException("rename failed");
        file = dst;
    }

    public void truncate(long byteOffset) throws IOException {
        RandomAccessFile raf = new RandomAccessFile(file, "rw");
        try {
            raf.setLength(byteOffset);
        } finally {
            raf.close();
        }
    }

    public void setFileConnection(String s) throws IOException {
        if (!file.isDirectory()) throw new IOException("not a directory");
        File child = "..".equals(s) ? file.getParentFile() : new File(file, s);
        if (child == null) throw new IOException("no parent");
        file = child;
    }

    public String getName() { return file.getName(); }
    public String getPath() { return file.getParent() + "/"; }
    public String getURL()  { return url; }
    public long lastModified() { return file.lastModified(); }

    public void close() throws IOException {
        open = false;
        try { if (cachedInput != null) cachedInput.close(); } catch (IOException ignored) {}
        try { if (cachedOutput != null) cachedOutput.close(); } catch (IOException ignored) {}
        cachedInput = null;
        cachedOutput = null;
    }
}
