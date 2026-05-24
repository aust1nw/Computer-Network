#ifndef TRANSPORT_HEADER_H
#define TRANSPORT_HEADER_H

#include "protocol.h"
#include "channels.h"

// TCP Flags
#define SYN_FLAG 1        // 0000 0001
#define ACK_FLAG 2        // 0000 0010
#define FIN_FLAG 4        // 0000 0100
#define RST_FLAG 8        // 0000 1000

enum{
  TCP_PACKET_HEADER_LENGTH = 8,
  TCP_PACKET_MAX_PAYLOAD_SIZE = 12
};

typedef nx_struct transport_header {
  nx_uint8_t src_port;     
  nx_uint8_t dest_port;    
  nx_uint8_t seq_num;       
  nx_uint8_t ack_num;
  nx_uint8_t last_ack;      
  nx_uint8_t flags;         
  nx_uint8_t window; 
  nx_uint8_t len;      
  nx_uint8_t payload[0];
} transport_header;

#endif