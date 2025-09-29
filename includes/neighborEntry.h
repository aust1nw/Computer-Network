#ifndef NEIGHBORENTRY_H
#define NEIGHBORENTRY_H

typedef struct{
    uint8_t count;
    uint16_t seq[10];
    float(uint16_t) numReceived;
    float(uint16_t) numReplied;
    float(uint16_t) average;
}NeighborEntry;

#endif