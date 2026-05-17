package javax.microedition.io.impl;

import java.io.IOException;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;

import javax.microedition.io.Datagram;
import javax.microedition.io.UDPDatagramConnection;

/**
 * MIDP UDPDatagramConnection on top of java.net.DatagramSocket. URL form:
 *   datagram://host:port  → client (remote endpoint fixed)
 *   datagram://:port      → server (bound, no fixed remote)
 *   datagram://           → ephemeral port, no fixed remote
 */
public class UDPDatagramConnectionImpl implements UDPDatagramConnection {

    private final DatagramSocket socket;
    private final String defaultHost;
    private final int defaultPort;

    /** @param host nullable; @param port -1 for ephemeral. */
    public UDPDatagramConnectionImpl(String host, int port) throws IOException {
        this.defaultHost = host;
        this.defaultPort = port;
        if (host == null) {
            // Server / bound: port is the local bind port (0 = ephemeral).
            this.socket = new DatagramSocket(port >= 0 ? port : 0);
        } else {
            // Client: pick an ephemeral local port; remote is implied by send().
            this.socket = new DatagramSocket();
        }
    }

    public int getMaximumLength() throws IOException {
        // Theoretical UDP payload max (65535 - 8 byte UDP header - 20 byte IPv4 header).
        return 65507;
    }

    public int getNominalLength() throws IOException {
        return getMaximumLength();
    }

    public void send(Datagram dgram) throws IOException {
        if (!(dgram instanceof DatagramImpl)) {
            throw new IOException("foreign Datagram impl");
        }
        DatagramImpl d = (DatagramImpl) dgram;
        byte[] payload = d.toBytes();
        String addr = d.getAddress();
        if (addr == null) addr = buildDefaultAddress();
        InetSocketAddress dst = parseAddress(addr);
        DatagramPacket pkt = new DatagramPacket(payload, payload.length, dst);
        socket.send(pkt);
    }

    public void receive(Datagram dgram) throws IOException {
        if (!(dgram instanceof DatagramImpl)) {
            throw new IOException("foreign Datagram impl");
        }
        DatagramImpl d = (DatagramImpl) dgram;
        byte[] buf = d.getData();
        DatagramPacket pkt = new DatagramPacket(buf, d.getOffset(), buf.length - d.getOffset());
        socket.receive(pkt);
        d.setReceivedLength(pkt.getLength());
        InetAddress from = pkt.getAddress();
        if (from != null) {
            d.setAddress("datagram://" + from.getHostAddress() + ":" + pkt.getPort());
        }
    }

    public Datagram newDatagram(int size) throws IOException {
        return new DatagramImpl(size);
    }

    public Datagram newDatagram(int size, String addr) throws IOException {
        return new DatagramImpl(size, addr);
    }

    public Datagram newDatagram(byte[] buf, int size) throws IOException {
        return new DatagramImpl(buf, size);
    }

    public Datagram newDatagram(byte[] buf, int size, String addr) throws IOException {
        return new DatagramImpl(buf, size, addr);
    }

    public String getLocalAddress() throws IOException {
        InetAddress local = socket.getLocalAddress();
        return local != null ? local.getHostAddress() : "0.0.0.0";
    }

    public int getLocalPort() throws IOException {
        return socket.getLocalPort();
    }

    public void close() throws IOException {
        socket.close();
    }

    private String buildDefaultAddress() throws IOException {
        if (defaultHost == null || defaultPort < 0) {
            throw new IOException("no destination address on Datagram and no default");
        }
        return "datagram://" + defaultHost + ":" + defaultPort;
    }

    /** Accepts "datagram://host:port" or "host:port". */
    private static InetSocketAddress parseAddress(String addr) throws IOException {
        String s = addr;
        int p = s.indexOf("://");
        if (p >= 0) s = s.substring(p + 3);
        int colon = s.lastIndexOf(':');
        if (colon <= 0) throw new IOException("bad datagram address: " + addr);
        String host = s.substring(0, colon);
        int port;
        try {
            port = Integer.parseInt(s.substring(colon + 1));
        } catch (NumberFormatException e) {
            throw new IOException("bad port: " + addr);
        }
        return new InetSocketAddress(InetAddress.getByName(host), port);
    }
}
