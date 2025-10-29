#ifndef FLOODING_H
#define FLOODING_H

#include "protocol.h"

enum{
    FLOODING_HEADER_LENGTH = 6,
    FLOODING_MAX_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE - FLOODING_HEADER_LENGTH
};

// Flooding Header (end-to-end control information)
typedef nx_struct flood_header{
    nx_uint16_t src;        // Original source that initiated flood
    nx_uint16_t seq;        // Sequence number (monotonically increasing per source)
    nx_uint16_t TTL;        // Time to live
    nx_uint8_t payload[0];  // Zero-length array for application payload
} flood_header;

#endif /* FLOODING_H */