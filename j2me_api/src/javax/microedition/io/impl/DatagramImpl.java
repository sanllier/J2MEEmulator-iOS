package javax.microedition.io.impl;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;

import javax.microedition.io.Datagram;

/**
 * In-memory Datagram backed by a byte[] for receive and a ByteArrayOutputStream
 * for write. The owning UDPDatagramConnectionImpl calls toBytes() before send
 * and setReceivedLength() after receive.
 */
public class DatagramImpl implements Datagram {

    private byte[] buf;
    private int offset;
    private int length;
    private String addr;

    private DataInputStream dis;
    private ByteArrayOutputStream baos;
    private DataOutputStream dos;

    public DatagramImpl(int size) {
        this(new byte[size], 0, size, null);
    }

    public DatagramImpl(int size, String addr) {
        this(new byte[size], 0, size, addr);
    }

    public DatagramImpl(byte[] buf, int len) {
        this(buf, 0, len, null);
    }

    public DatagramImpl(byte[] buf, int len, String addr) {
        this(buf, 0, len, addr);
    }

    private DatagramImpl(byte[] buf, int off, int len, String addr) {
        if (buf == null) throw new IllegalArgumentException("buf is null");
        if (off < 0 || len < 0 || off + len > buf.length) {
            throw new IllegalArgumentException("bad offset/length");
        }
        this.buf = buf;
        this.offset = off;
        this.length = len;
        this.addr = addr;
    }

    public String getAddress() { return addr; }
    public byte[] getData() { return buf; }
    public int getLength() { return length; }
    public int getOffset() { return offset; }

    public void setAddress(String a) {
        addr = a;
    }

    public void setAddress(Datagram reference) {
        addr = reference.getAddress();
    }

    public void setLength(int len) {
        if (len < 0 || offset + len > buf.length) throw new IllegalArgumentException();
        length = len;
        resetStreams();
    }

    public void setData(byte[] buffer, int off, int len) {
        if (buffer == null) throw new NullPointerException();
        if (off < 0 || len < 0 || off + len > buffer.length) {
            throw new IllegalArgumentException();
        }
        this.buf = buffer;
        this.offset = off;
        this.length = len;
        resetStreams();
    }

    public void reset() {
        length = 0;
        resetStreams();
    }

    // ---- helpers used by UDPDatagramConnectionImpl ----

    /** Snapshot of bytes to send: writeXxx output if any, otherwise current buf slice. */
    public byte[] toBytes() {
        if (baos != null && baos.size() > 0) {
            byte[] out = baos.toByteArray();
            // Mirror into the configured slice so getData/getLength reflect what was sent.
            if (out.length + offset <= buf.length) {
                System.arraycopy(out, 0, buf, offset, out.length);
            }
            length = out.length;
            return out;
        }
        byte[] out = new byte[length];
        System.arraycopy(buf, offset, out, 0, length);
        return out;
    }

    public void setReceivedLength(int len) {
        this.length = len;
        resetStreams();
    }

    private void resetStreams() {
        dis = null;
        baos = null;
        dos = null;
    }

    private DataInputStream in() {
        if (dis == null) {
            dis = new DataInputStream(new ByteArrayInputStream(buf, offset, length));
        }
        return dis;
    }

    private DataOutputStream out() {
        if (dos == null) {
            baos = new ByteArrayOutputStream();
            dos = new DataOutputStream(baos);
        }
        return dos;
    }

    // ---- DataInput ----
    public boolean readBoolean() throws IOException { return in().readBoolean(); }
    public byte readByte() throws IOException { return in().readByte(); }
    public char readChar() throws IOException { return in().readChar(); }
    public double readDouble() throws IOException { return in().readDouble(); }
    public float readFloat() throws IOException { return in().readFloat(); }
    public void readFully(byte[] b) throws IOException { in().readFully(b); }
    public void readFully(byte[] b, int off, int len) throws IOException { in().readFully(b, off, len); }
    public int readInt() throws IOException { return in().readInt(); }
    public String readLine() throws IOException { return in().readLine(); }
    public long readLong() throws IOException { return in().readLong(); }
    public short readShort() throws IOException { return in().readShort(); }
    public int readUnsignedByte() throws IOException { return in().readUnsignedByte(); }
    public int readUnsignedShort() throws IOException { return in().readUnsignedShort(); }
    public String readUTF() throws IOException { return in().readUTF(); }
    public int skipBytes(int n) throws IOException { return in().skipBytes(n); }

    // ---- DataOutput ----
    public void write(int b) throws IOException { out().write(b); }
    public void write(byte[] b) throws IOException { out().write(b); }
    public void write(byte[] b, int off, int len) throws IOException { out().write(b, off, len); }
    public void writeBoolean(boolean v) throws IOException { out().writeBoolean(v); }
    public void writeByte(int v) throws IOException { out().writeByte(v); }
    public void writeBytes(String s) throws IOException { out().writeBytes(s); }
    public void writeChar(int v) throws IOException { out().writeChar(v); }
    public void writeChars(String s) throws IOException { out().writeChars(s); }
    public void writeDouble(double v) throws IOException { out().writeDouble(v); }
    public void writeFloat(float v) throws IOException { out().writeFloat(v); }
    public void writeInt(int v) throws IOException { out().writeInt(v); }
    public void writeLong(long v) throws IOException { out().writeLong(v); }
    public void writeShort(int v) throws IOException { out().writeShort(v); }
    public void writeUTF(String s) throws IOException { out().writeUTF(s); }
}
