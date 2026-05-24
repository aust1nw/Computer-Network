#ifndef IP_HEADER_H
#define IP_HEADER_H

enum{
    IP_HEADER_LENGTH = 4,
    DEFAULT_TTL = 64
};

typedef nx_struct ip_header{
    nx_uint8_t src;
    nx_uint8_t dest;
    nx_uint8_t TTL;
    nx_uint8_t protocol;
    nx_uint8_t payload[0];
} ip_header;

#endif 