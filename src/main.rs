#![allow(non_upper_case_globals, non_camel_case_types, non_snake_case, dead_code)]
use std::net::UdpSocket;
use std::thread;
use std::time::Duration;

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

fn main() {
    unsafe {
        let mut board_conf: lgw_conf_board_s = std::mem::zeroed();
        board_conf.lorawan_public = false;
        board_conf.clksrc = 0;
        board_conf.full_duplex = false;
        board_conf.com_type = 0;
        
        let path = b"/dev/spidev0.0\0";
        for (i, &b) in path.iter().enumerate() {
            board_conf.com_path[i] = b as std::os::raw::c_char;
        }
        
        if lgw_board_setconf(&mut board_conf) != 0 { panic!("Board config failed!"); }

        let mut rxrf_conf0: lgw_conf_rxrf_s = std::mem::zeroed();
        rxrf_conf0.enable = true;
        rxrf_conf0.freq_hz = 869525000; 
        rxrf_conf0.type_ = lgw_radio_type_t_LGW_RADIO_TYPE_SX1250;
        rxrf_conf0.tx_enable = true;
        lgw_rxrf_setconf(0, &mut rxrf_conf0);

        let mut rxrf_conf1: lgw_conf_rxrf_s = std::mem::zeroed();
        rxrf_conf1.enable = false;
        lgw_rxrf_setconf(1, &mut rxrf_conf1);

        for i in 0..8 {
            let mut if_conf: lgw_conf_rxif_s = std::mem::zeroed();
            if_conf.enable = false;
            lgw_rxif_setconf(i, &mut if_conf);
        }

        let mut if8_conf: lgw_conf_rxif_s = std::mem::zeroed();
        if8_conf.enable = true;
        if8_conf.rf_chain = 0;       
        if8_conf.freq_hz = 0;        
        if8_conf.bandwidth = 5;
        if8_conf.datarate = 8;
        if8_conf.implicit_hdr = false; 
        lgw_rxif_setconf(8, &mut if8_conf);

        if lgw_start() != 0 { panic!("SX1302 start failed!"); }
        
        let socket = UdpSocket::bind("127.0.0.1:4242").expect("Could not bind UDP socket");
        socket.set_nonblocking(true).expect("Could not set socket to non-blocking");
        let rnsd_addr = "127.0.0.1:4243";

        println!("==================================================");
        println!("[+] RAK2Reticulum NATIVE BRIDGE ONLINE");
        println!("==================================================");

        //let mut rx_packets: [lgw_pkt_rx_s; 16] = std::mem::zeroed();
	// Allocate 32 on the heap to create a massive memory crumple zone.
	// This prevents C-side overruns from touching the Rust stack.
	let mut rx_packets = vec![std::mem::zeroed::<lgw_pkt_rx_s>(); 32];
        loop {
            let num_packets = lgw_receive(16, rx_packets.as_mut_ptr());
            if num_packets > 0 {
                for i in 0..num_packets as usize {
                    let pkt = &rx_packets[i];
                    if pkt.status == 0x10 { 
                        let safe_size = std::cmp::min(pkt.size as usize, 255);
                        let payload_slice = std::slice::from_raw_parts(pkt.payload.as_ptr(), safe_size);
                        let hex_payload: String = payload_slice.iter().map(|b| format!("{:02x}", b)).collect();
                        
                        println!("[RX] RSSI: {:.1} dBm | SNR: {:.1} dB | Len: {} bytes", pkt.rssic, pkt.snr, safe_size);
                        println!("    => Payload: {}", hex_payload);

                        socket.send_to(payload_slice, rnsd_addr).ok();
                    }
                }
            }

            let mut buf = [0u8; 500];
            if let Ok((size, _)) = socket.recv_from(&mut buf) {
                if size > 255 {
                    println!("[WARN] Dropped oversized TX packet from Reticulum: {} bytes", size);
                } else {
                    //let mut tx_pkt: lgw_pkt_tx_s = std::mem::zeroed();
                    let mut tx_pkt = Box::new(std::mem::zeroed::<lgw_pkt_tx_s>());
		    tx_pkt.freq_hz = 869525000; 
                    tx_pkt.tx_mode = 0;           
                    tx_pkt.rf_power = 27;         
                    tx_pkt.modulation = 0x10;     
                    tx_pkt.bandwidth = 5;
                    tx_pkt.datarate = 8;
                    tx_pkt.coderate = 1;
                    tx_pkt.preamble = 8;
                    tx_pkt.size = size as u16;
                    tx_pkt.payload[..size].copy_from_slice(&buf[..size]);
                    
                    if lgw_send(&mut *tx_pkt) == 0 {
                        let tx_payload_slice = &buf[..size];
                        let hex_payload: String = tx_payload_slice.iter().map(|b| format!("{:02x}", b)).collect();
                        println!("[TX] Len: {} bytes", size);
                        println!("    => Payload: {}", hex_payload);
                    } else {
                        println!("[ERR] TX Failed");
                    }
                }
            }
            thread::sleep(Duration::from_millis(5));
        }
    }
}
