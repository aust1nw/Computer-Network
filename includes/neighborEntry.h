#ifndef NEIGHBORENTRY_H
#define NEIGHBORENTRY_H

typedef struct{
    uint8_t count;
    uint16_t seq[10];
}__attribute__((packed)) NeighborEntry;

#endif