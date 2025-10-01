#ifndef NEIGHBORENTRY_H
#define NEIGHBORENTRY_H

typedef struct{
    uint8_t count;
    uint16_t seq[10];
    uint16_t numReceived;
    uint16_t numReplied;
    uint16_t average;
    uint32_t lastHeard;
}NeighborEntry;

#endif