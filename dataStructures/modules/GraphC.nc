#include "../../includes/channels.h"
// can be adjusted later
#define MAX_NODES 50
#define MAX_NEIGHBORS_PER_NODE 20

generic module GraphC(){
    provides interface Graph;
}

implementation{
    typedef struct {
        uint16_t edges[MAX_NODES][MAX_NEIGHBORS_PER_NODE];
        uint16_t costs[MAX_NODES][MAX_NEIGHBORS_PER_NODE];  // Edge costs
        uint8_t neighborCount[MAX_NODES];
        bool nodeExists[MAX_NODES];
        uint16_t nodeCount;
        uint16_t edgeCount;
    } Graph_t;

    Graph_t graph;

    // Helper function
    bool hasEdgeHelper(uint16_t u, uint16_t v) {
        uint8_t i;
        if (!graph.nodeExists[u] || !graph.nodeExists[v]) {
            return FALSE;
        }
        
        for (i = 0; i < graph.neighborCount[u]; i++) {
            if (graph.edges[u][i] == v) {
                return TRUE;
            }
        }
        return FALSE;
    }

    // Initialize the graph
    task void initGraph() {
        uint16_t i, j;
        for (i = 0; i < MAX_NODES; i++) {
            graph.neighborCount[i] = 0;
            graph.nodeExists[i] = FALSE;
            for (j = 0; j < MAX_NEIGHBORS_PER_NODE; j++) {
                graph.edges[i][j] = 0xFFFF;
                graph.costs[i][j] = 0xFFFF;  // Infinite cost
            }
        }
        graph.nodeCount = 0;
        graph.edgeCount = 0;
    }
    
    command void Graph.addEdge(uint16_t u, uint16_t v, uint16_t cost) {
        uint8_t i;
        uint8_t j;

        if(cost == 0){
            cost = 1;
        }
        
        // Check if nodes exist, if not add them
        if (!graph.nodeExists[u]) {
            graph.nodeExists[u] = TRUE;
            graph.nodeCount++;
        }
        if (!graph.nodeExists[v]) {
            graph.nodeExists[v] = TRUE;
            graph.nodeCount++;
        }
        
        // Check if edge already exists - if so, just update cost
        for (i = 0; i < graph.neighborCount[u]; i++) {
            if (graph.edges[u][i] == v) {
                graph.costs[u][i] = cost;  // Update existing edge cost
                
                // Update reverse edge cost too
                for (j = 0; j < graph.neighborCount[v]; j++) {
                    if (graph.edges[v][j] == u) {
                        graph.costs[v][j] = cost;
                        break;
                    }
                }
                return;
            }
        }
        
        // Add new edge to adjacency list
        if (graph.neighborCount[u] < MAX_NEIGHBORS_PER_NODE) {
            graph.edges[u][graph.neighborCount[u]] = v;
            graph.costs[u][graph.neighborCount[u]] = cost;
            graph.neighborCount[u]++;
            graph.edgeCount++;
        }
        
        // For undirected graph, add reverse edge
        if (graph.neighborCount[v] < MAX_NEIGHBORS_PER_NODE) {
            graph.edges[v][graph.neighborCount[v]] = u;
            graph.costs[v][graph.neighborCount[v]] = cost;
            graph.neighborCount[v]++;
        }
    }
    
    command uint16_t Graph.getCost(uint16_t u, uint16_t v) {
        uint8_t i;
        
        if (!graph.nodeExists[u] || !graph.nodeExists[v]) {
            return 0xFFFF;  // Infinite cost
        }
        
        for (i = 0; i < graph.neighborCount[u]; i++) {
            if (graph.edges[u][i] == v) {
                return graph.costs[u][i];
            }
        }
        
        return 0xFFFF;  // No edge exists
    }
    
    command void Graph.removeEdge(uint16_t u, uint16_t v) {
        uint8_t i;
        uint8_t j;
        bool found = FALSE;
        
        // Remove v from u's neighbors
        for (i = 0; i < graph.neighborCount[u]; i++) {
            if (graph.edges[u][i] == v) {
                // Shift remaining elements
                for (j = i; j < graph.neighborCount[u] - 1; j++) {
                    graph.edges[u][j] = graph.edges[u][j + 1];
                    graph.costs[u][j] = graph.costs[u][j + 1];  // Shift costs too
                }
                graph.neighborCount[u]--;
                graph.edgeCount--;
                found = TRUE;
                break;
            }
        }
        
        // Remove u from v's neighbors (for undirected graph)
        if (found) {
            for (i = 0; i < graph.neighborCount[v]; i++) {
                if (graph.edges[v][i] == u) {
                    for (j = i; j < graph.neighborCount[v] - 1; j++) {
                        graph.edges[v][j] = graph.edges[v][j + 1];
                        graph.costs[v][j] = graph.costs[v][j + 1];  // Shift costs too
                    }
                    graph.neighborCount[v]--;
                    break;
                }
            }
        }
    }

    command void Graph.clearNodeEdges(uint16_t node) {
        uint8_t i, j;
        
        // Check if node has any neighbors
        if (graph.neighborCount[node] == 0) {
            return;
        }
        
        // Remove all edges FROM this node to its neighbors
        for (i = 0; i < graph.neighborCount[node]; i++) {
            uint16_t neighbor = graph.edges[node][i];
            
            if (neighbor == 0xFFFF) continue;  // Skip invalid entries
            
            // Remove the reverse edge (neighbor -> node)
            for (j = 0; j < graph.neighborCount[neighbor]; j++) {
                if (graph.edges[neighbor][j] == node) {
                    // Shift remaining elements to remove this edge
                    uint8_t k;
                    for (k = j; k < graph.neighborCount[neighbor] - 1; k++) {
                        graph.edges[neighbor][k] = graph.edges[neighbor][k + 1];
                        graph.costs[neighbor][k] = graph.costs[neighbor][k + 1];
                    }
                    // Clear the last element
                    graph.edges[neighbor][graph.neighborCount[neighbor] - 1] = 0xFFFF;
                    graph.costs[neighbor][graph.neighborCount[neighbor] - 1] = 0xFFFF;
                    graph.neighborCount[neighbor]--;
                    graph.edgeCount--;
                    break;
                }
            }
        }
        
        // Reset this node's edges
        graph.neighborCount[node] = 0;
        for (i = 0; i < MAX_NEIGHBORS_PER_NODE; i++) {
            graph.edges[node][i] = 0xFFFF;
            graph.costs[node][i] = 0xFFFF;
        }
    }
    
    command bool Graph.hasEdge(uint16_t u, uint16_t v) {
        return hasEdgeHelper(u, v);
    }
    
    command uint16_t Graph.getNeighborCount(uint16_t node) {
        if (!graph.nodeExists[node]) {
            return 0;
        }
        return graph.neighborCount[node];
    }
    
    command uint16_t* Graph.getNeighbors(uint16_t node) {
        if (!graph.nodeExists[node] || graph.neighborCount[node] == 0) {
            return NULL;
        }
        return graph.edges[node];
    }
    
    command void Graph.clearGraph() {
        post initGraph();
    }
    
    command uint16_t Graph.getNodeCount() {
        return graph.nodeCount;
    }
    
    command uint16_t Graph.getEdgeCount() {
        return graph.edgeCount;
    }
}