#ifndef IP_HEADER_H
#define IP_HEADER_H

enum{
    IP_HEADER_LENGTH = 6,
    DEFAULT_TTL = 15
};

typedef nx_struct ip_header{
    nx_uint16_t src;
    nx_uint16_t dest;
    nx_uint8_t TTL;
    nx_uint8_t protocol;
    nx_uint8_t payload[0];
} ip_header;

#endif 