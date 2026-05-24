#ifndef RING_H
#define RING_H

typedef struct{
    uint8_t buf[256];
    uint16_t w, r;
} ring_t;

#endif // RING_H