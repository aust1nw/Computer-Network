#ifndef LSA_H
#define LSA_H

#define MAX_NODES 50
#define MAX_NEIGHBORS 20

// Link State Advertisement packet
typedef nx_struct LSA {
    nx_uint16_t nodeID;                      // Node that generated this LSA
    nx_uint16_t seq;                         // Sequence number
    nx_uint8_t numNeighbors;                 // Number of neighbors
    nx_uint16_t neighbors[MAX_NEIGHBORS];    // Neighbor IDs
    nx_uint16_t costs[MAX_NEIGHBORS];    // Link costs to each neighbor
} LSA;

#endif