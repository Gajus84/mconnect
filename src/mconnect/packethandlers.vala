/* ex:ts=4:sw=4:sts=4:et */
/* -*- tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
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

class PacketHandlers : Object {

	private List<PacketHandlerInterface> _handlers = null;

	public List<PacketHandlerInterface> handlers {
		get {
			return _handlers;
		}
		private set {
			_handlers = handlers.copy();
		}
	}
	public string[] interfaces { get; private set; default = null; }

	public PacketHandlers() {
		_handlers = load_handlers();
		string [] ifaces;
		list_handlers(out ifaces);
		interfaces = ifaces;
	}

	private static List<PacketHandlerInterface> load_handlers() {
		List<PacketHandlerInterface> hnd = new List<PacketHandlerInterface>();

		var notification = NotificationHandler.instance();
		var battery = BatteryHandler.instance();
		var telephony = TelephonyHandler.instance();

		hnd.append(notification);
		hnd.append(battery);
		hnd.append(telephony);

		return hnd;
	}

	public void list_handlers(out string[] interfaces) {
		interfaces = new string[_handlers.length()];
		// string[] interfaces = new string[_handlers.length()];
		for (int i = 0; i < _handlers.length(); i++) {
			interfaces[i] = _handlers.nth_data(i).get_pkt_type();
		}
		// return interfaces;
	}

	public void use_device(Device dev) {
		_handlers.foreach((h) => {
				h.use_device(dev);
			});
	}
}