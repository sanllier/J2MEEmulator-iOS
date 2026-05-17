package javax.microedition.io.impl;

import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketException;

import javax.microedition.io.SocketConnection;

/**
 * MIDP SocketConnection on top of java.net.Socket. URL form:
 *   socket://host:port  → client connection
 *   socket://:port      → server socket (delegated to ServerSocketConnectionImpl by Connector)
 */
public class SocketConnectionImpl implements SocketConnection {

    private final Socket socket;
    private InputStream cachedInput;
    private OutputStream cachedOutput;

    public SocketConnectionImpl(String host, int port) throws IOException {
        this.socket = new Socket();
        this.socket.connect(new InetSocketAddress(host, port));
    }

    /** Wraps an accepted Socket from ServerSocketConnectionImpl.acceptAndOpen(). */
    public SocketConnectionImpl(Socket accepted) {
        this.socket = accepted;
    }

    public InputStream openInputStream() throws IOException {
        if (cachedInput == null) cachedInput = socket.getInputStream();
        return cachedInput;
    }

    public DataInputStream openDataInputStream() throws IOException {
        return new DataInputStream(openInputStream());
    }

    public OutputStream openOutputStream() throws IOException {
        if (cachedOutput == null) cachedOutput = socket.getOutputStream();
        return cachedOutput;
    }

    public DataOutputStream openDataOutputStream() throws IOException {
        return new DataOutputStream(openOutputStream());
    }

    public void close() throws IOException {
        socket.close();
    }

    public void setSocketOption(byte option, int value)
            throws IllegalArgumentException, IOException {
        try {
            switch (option) {
                case DELAY:     socket.setTcpNoDelay(value == 0); break; // 0=enable Nagle, 1=disable
                case LINGER:    socket.setSoLinger(value > 0, value); break;
                case KEEPALIVE: socket.setKeepAlive(value != 0); break;
                case RCVBUF:    socket.setReceiveBufferSize(value); break;
                case SNDBUF:    socket.setSendBufferSize(value); break;
                default: throw new IllegalArgumentException("unknown option: " + option);
            }
        } catch (SocketException e) {
            throw new IOException(e.getMessage());
        }
    }

    public int getSocketOption(byte option)
            throws IllegalArgumentException, IOException {
        try {
            switch (option) {
                case DELAY:     return socket.getTcpNoDelay() ? 1 : 0;
                case LINGER:    return socket.getSoLinger();
                case KEEPALIVE: return socket.getKeepAlive() ? 1 : 0;
                case RCVBUF:    return socket.getReceiveBufferSize();
                case SNDBUF:    return socket.getSendBufferSize();
                default: throw new IllegalArgumentException("unknown option: " + option);
            }
        } catch (SocketException e) {
            throw new IOException(e.getMessage());
        }
    }

    public String getLocalAddress() throws IOException {
        return socket.getLocalAddress().getHostAddress();
    }

    public int getLocalPort() throws IOException {
        return socket.getLocalPort();
    }

    public String getAddress() throws IOException {
        return socket.getInetAddress().getHostAddress();
    }

    public int getPort() throws IOException {
        return socket.getPort();
    }
}
