interface Graph{
    // Add edge with cost
    command void addEdge(uint16_t u, uint16_t v, uint16_t cost);
    
    // Remove edge
    command void removeEdge(uint16_t u, uint16_t v);
    
    // Check if edge exists
    command bool hasEdge(uint16_t u, uint16_t v);
    
    // Get cost of edge
    command uint16_t getCost(uint16_t u, uint16_t v);
    
    // Get neighbor count
    command uint16_t getNeighborCount(uint16_t node);
    
    // Get neighbors array
    command uint16_t* getNeighbors(uint16_t node);
    
    // Clear graph
    command void clearGraph();
    
    // Get graph stats
    command uint16_t getNodeCount();
    command uint16_t getEdgeCount();

    command void clearNodeEdges(uint16_t node);
}