/**
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * AUTHORS
 * Maciek Borzecki <maciek.borzecki (at] gmail.com>
 */

class UploadTransfer : TransferInterface, Object {

    private FileInputStream finstream = null;
    private Cancellable cancellable = null;
    private Device device = null;
    private TlsConnection tls_conn = null;
    private SocketService listener = null;
    private uint timeout_source = 0;
    private IOCopyJob job = null;
    private SocketConnection conn = null;
    private uint64 transferred = 0;
    private uint64 size;
    private Notify.Notification notif = null;
    private string title = null;
    private string icon = null;

    private const int WAIT_TIMEOUT = 30;

    public UploadTransfer (Device dev, SocketService listener,
                           FileInputStream source, uint64 size, string filename) {
        this.listener = listener;
        this.cancellable = new Cancellable ();
        this.device = dev;
        this.finstream = source;
        this.size = size;
        this.notif = new Notify.Notification ("Transfer", "Start transfer",
                                              "phone");
        this.title = "Transfer %s".printf(filename);
        this.icon = "phone";
    }

    public async bool start_async () {
        debug ("start transfer from to device %s",
               this.device.to_string ());

        this.listener.incoming.connect (this.client_connected);
        debug ("wait for client");
        this.timeout_source = Timeout.add_seconds (WAIT_TIMEOUT,
                                                   this.wait_timeout);
        this.listener.start ();

        return true;
    }

    private bool wait_timeout () {
        warning ("timeout waiting for client");
        this.listener.stop ();
        this.cleanup_error ("timeout waiting for client");
        return false;
    }

    private bool client_connected (SocketConnection conn, Object ? source) {
        if (this.timeout_source != 0) {
            Source.remove (this.timeout_source);
            this.timeout_source = 0;
        }

        this.handle_client.begin (conn);
        return false;
    }

    private async void handle_client (SocketConnection conn) {
        InetSocketAddress isa;
        try {
            isa = conn.get_remote_address () as InetSocketAddress;
        } catch (Error e) {
            warning ("cannot obtain remote address: %s", e.message);
            return;
        }
        debug ("client connected: %s:%u", isa.address.to_string (),
               isa.port);

        this.conn = conn;

        var sock = this.conn.get_socket ();
        Utils.socket_set_keepalive (sock);

        // enable TLS
        this.tls_conn = Utils.make_tls_connection (this.conn,
                                                   Core.instance ().certificate,
                                                   this.device.certificate,
                                                   Utils.TlsConnectionMode.SERVER);
        try {
            debug ("attempt TLS handshake");
            yield this.tls_conn.handshake_async ();

            debug ("TLS handshake complete");
        } catch (Error e) {
            var err = "TLS handshake failed: %s".printf (e.message);
            warning (err);
            this.cleanup_error (err);
            return;
        }

        this.start_transfer ();
    }

    private void start_transfer () {
        debug ("connected, start transfer");
        this.job = new IOCopyJob (this.finstream,
                                  this.tls_conn.output_stream);
        var lastupdate = (int64)0;
        this.job.progress.connect ((t, done) => {
            int percent = (int) (100.0 * ((double) done / (double) this.size));
            string message = "progress: %s/%s".printf(
                   format_size (done), format_size (this.size));
            debug (message);
            this.notif.update(this.title, message, this.icon);
            this.notif.set_hint("value", percent);
            var now = new DateTime.now_local().to_unix();
            if (now - lastupdate >= 2) {
                lastupdate = now;
                this.show_notification();
            }
            this.transferred = done;
        });

        this.started ();

        this.job.start_async.begin (this.cancellable,
                                    this.job_complete);
    }

    private void show_notification() {
        try {
            this.notif.show ();
        } catch (Error e) {
            critical ("failed to show notification: %s", e.message);
        }
    }

    private void job_complete (Object ? obj, AsyncResult res) {
        info ("transfer finished");
        this.notif.update(this.title, "Complete", this.icon);
        this.show_notification();
        try {
            var rcvd_bytes = this.job.start_async.end (res);
            debug ("transfer done, got %s", format_size (rcvd_bytes));

            this.cleanup_success ();
        } catch (Error err) {
            warning ("transfer failed: %s", err.message);

            this.cleanup_error (err.message);
        }
    }

    private void cleanup () {
        if (this.finstream != null) {
            try {
                this.finstream.close ();
            } catch (IOError e) {
                warning ("failed to close file input: %s",
                         e.message);
            }
        }

        if (this.tls_conn != null) {
            try {
                this.tls_conn.close ();
            } catch (IOError e) {
                warning ("failed to close TLS connection: %s",
                         e.message);
            }
        }
        if (this.conn != null) {
            try {
                this.conn.close ();
            } catch (IOError e) {
                warning ("failed to close connection: %s",
                         e.message);
            }
        }

        this.listener.stop ();
        this.listener.close ();
        this.finstream = null;
        this.conn = null;
        this.tls_conn = null;
        this.job = null;
    }

    private void cleanup_error (string reason) {

        this.cleanup ();

        this.error (reason);
    }

    private void cleanup_success () {
        this.cleanup ();

        this.finished ();
    }

    public void cancel () {
        debug ("cancel called");
        this.cancellable.cancel ();
    }
}
