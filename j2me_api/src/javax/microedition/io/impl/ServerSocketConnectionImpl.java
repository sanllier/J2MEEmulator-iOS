package javax.microedition.io.impl;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.ServerSocket;

import javax.microedition.io.ServerSocketConnection;
import javax.microedition.io.StreamConnection;

/**
 * MIDP ServerSocketConnection on top of java.net.ServerSocket. URL form:
 *   socket://:port        (used by Connector for "socket://" with no host)
 *   serversocket://:port  (explicit)
 *   serversocket://       (any free port)
 */
public class ServerSocketConnectionImpl implements ServerSocketConnection {

    private final ServerSocket server;

    public ServerSocketConnectionImpl(int port) throws IOException {
        this.server = new ServerSocket();
        this.server.bind(new InetSocketAddress(port));
    }

    public StreamConnection acceptAndOpen() throws IOException {
        return new SocketConnectionImpl(server.accept());
    }

    public String getLocalAddress() throws IOException {
        return server.getInetAddress().getHostAddress();
    }

    public int getLocalPort() throws IOException {
        return server.getLocalPort();
    }

    public void close() throws IOException {
        server.close();
    }
}
