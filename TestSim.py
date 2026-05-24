#ANDES Lab - University of California, Merced
#Author: UCM ANDES Lab
#$Author: abeltran2 $
#$LastChangedDate: 2014-08-31 16:06:26 -0700 (Sun, 31 Aug 2014) $
#! /usr/bin/python
import sys
from TOSSIM import *
from CommandMsg import *

class TestSim:
    moteids=[]
    # COMMAND TYPES
    CMD_PING = 0
    CMD_NEIGHBOR_DUMP = 1
    CMD_LINKSTATE_DUMP = 2
    CMD_ROUTE_DUMP = 3
    CMD_TEST_CLIENT = 4
    CMD_TEST_SERVER = 5
    CMD_CLIENT_CLOSE = 6
    CMD_APP_CLIENT = 10
    CMD_APP_SERVER = 11

    # CHANNELS - see includes/channels.h
    COMMAND_CHANNEL="command";
    GENERAL_CHANNEL="general";

    # Project 1
    NEIGHBOR_CHANNEL="neighbor";
    FLOODING_CHANNEL="flooding";

    # Project 2
    ROUTING_CHANNEL="routing";

    # Project 3
    TRANSPORT_CHANNEL="transport";

    # Personal Debuggin Channels for some of the additional models implemented.
    HASHMAP_CHANNEL="hashmap";

    # Initialize Vars
    numMote=0

    def __init__(self):
        self.t = Tossim([])
        self.r = self.t.radio()

        #Create a Command Packet
        self.msg = CommandMsg()
        self.pkt = self.t.newPacket()
        self.pkt.setType(self.msg.get_amType())

    # Load a topo file and use it.
    def loadTopo(self, topoFile):
        print 'Creating Topo!'
        # Read topology file.
        topoFile = 'topo/'+topoFile
        f = open(topoFile, "r")
        self.numMote = int(f.readline());
        print 'Number of Motes', self.numMote
        for line in f:
            s = line.split()
            if s:
                print " ", s[0], " ", s[1], " ", s[2];
                self.r.add(int(s[0]), int(s[1]), float(s[2]))
                if not int(s[0]) in self.moteids:
                    self.moteids=self.moteids+[int(s[0])]
                if not int(s[1]) in self.moteids:
                    self.moteids=self.moteids+[int(s[1])]

    # Load a noise file and apply it.
    def loadNoise(self, noiseFile):
        if self.numMote == 0:
            print "Create a topo first"
            return;

        # Get and Create a Noise Model
        noiseFile = 'noise/'+noiseFile;
        noise = open(noiseFile, "r")
        for line in noise:
            str1 = line.strip()
            if str1:
                val = int(str1)
            for i in self.moteids:
                self.t.getNode(i).addNoiseTraceReading(val)

        for i in self.moteids:
            print "Creating noise model for ",i;
            self.t.getNode(i).createNoiseModel()

    def bootNode(self, nodeID):
        if self.numMote == 0:
            print "Create a topo first"
            return;
        self.t.getNode(nodeID).bootAtTime(1333*nodeID);

    def bootAll(self):
        i=0;
        for i in self.moteids:
            self.bootNode(i);

    def moteOff(self, nodeID):
        self.t.getNode(nodeID).turnOff();

    def moteOn(self, nodeID):
        self.t.getNode(nodeID).turnOn();

    def run(self, ticks):
        for i in range(ticks):
            self.t.runNextEvent()

    # Rough run time. tickPerSecond does not work.
    def runTime(self, amount):
        self.run(amount*1000)

    # Generic Command
    def sendCMD(self, ID, dest, payloadStr):
        self.msg.set_dest(dest);
        self.msg.set_id(ID);
        self.msg.setString_payload(payloadStr)

        self.pkt.setData(self.msg.data)
        self.pkt.setDestination(dest)
        self.pkt.deliver(dest, self.t.time()+5)

    def ping(self, source, dest, msg):
        self.sendCMD(self.CMD_PING, source, "{0}{1}".format(chr(dest),msg));

    def neighborDMP(self, destination):
        self.sendCMD(self.CMD_NEIGHBOR_DUMP, destination, "neighbor command");

    def routeDMP(self, destination):
        self.sendCMD(self.CMD_ROUTE_DUMP, destination, "routing command");

    def addChannel(self, channelName, out=sys.stdout):
        print 'Adding Channel', channelName;
        self.t.addChannel(channelName, out);

    # The following are for Project 3
    def testClient(self, destination):
        self.sendCMD(self.CMD_TEST_CLIENT, destination, "client");
	
    def testServer(self, destination):
        self.sendCMD(self.CMD_TEST_SERVER, destination, "server");

    def appClient(self, destination, port):
        self.sendCMD(self.CMD_APP_CLIENT, destination, "{0}".format(port));
    
    def appServer(self, destination):
        self.sendCMD(self.CMD_APP_SERVER, destination, "appserver");

    def chat(self, node, text):
        self.msg.set_dest(node);
        self.msg.set_id(self.CMD_PING); # Reusing Ping ID
        self.msg.setString_payload("D" + text); # Just the text
        
        self.pkt.setData(self.msg.data);
        self.pkt.setDestination(node);
        self.pkt.deliver(node, self.t.time()+5);

    def clientClose(self, client_address, dest, srcPort, destPort):
        # Terminates the connection gracefully on the socket associated with 
        # [client_address], [srcPort], [destPort], and [dest].
        payload = "{0},{1},{2}".format(dest, srcPort, destPort)
        self.sendCMD(self.CMD_CLIENT_CLOSE, client_address, payload)
        print "Command sent to close connection from {0}:{1} to {2}:{3}".format(client_address, srcPort, dest, destPort)


def main():
    s = TestSim();
    # s.runTime(20);
    s.runTime(1);
    # s.loadTopo("long_line.topo");
    s.loadTopo("tuna-melt.topo");
    s.loadNoise("no_noise.txt");
    s.bootAll();
    s.addChannel(s.COMMAND_CHANNEL);
    # s.addChannel(s.GENERAL_CHANNEL);
    # s.addChannel(s.NEIGHBOR_CHANNEL);
    # s.addChannel(s.FLOODING_CHANNEL);
    # s.addChannel(s.ROUTING_CHANNEL);
    # s.addChannel(s.TRANSPORT_CHANNEL);

    # # After sending a ping, simulate a little to prevent collision.
    s.runTime(5000);
    
    # "Start server at node 1, port 123"
    # s.testServer(1);
    # s.runTime(1);

    # "Start client at node 4, connecting from port 200 to node 1 port 123, transfer 1000 bytes"
    # s.testClient(4);
    # s.runTime(10000);

    s.appServer(1);
    s.runTime(100);

    # s.appClient(2, 50);
    # s.runTime(300);

    s.appClient(4, 200);
    s.runTime(300);

    s.appClient(5, 100);
    s.runTime(300);

    s.chat(4, "msg 1st from 4");
    s.runTime(2000);
    s.chat(4, "listusr");
    s.runTime(2000);
    s.chat(4, "whisper u5 secret");
    s.runTime(3000);
    s.chat(4,"quit");
    s.chat(5,"quit");

    s.runTime(1000);
    

if __name__ == '__main__':
    main()
