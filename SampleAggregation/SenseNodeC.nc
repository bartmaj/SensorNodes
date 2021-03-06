#include <stdlib.h>
#include "../Messages.h"
#include "printf.h"

/**
 * Implementation of SenseNodeAppC
 * @authors John Berlin, Bartosz Maj
 */
module SenseNodeC {
	uses {
		interface Boot;
		interface Leds;

		interface SplitControl as RadioControl;

		interface Packet as SensePkt;
		interface Packet as ReportPkt;
		interface Packet as RecPkt;
		interface AMSend as SendSense;
		interface AMSend as SendReq;
		interface AMSend as SendReport;

		interface Receive as RecSense;
		interface Receive as RecRmsg;

		interface ReadConvertTL<uint16_t> as ReadTL;
		interface LocalTime<TMilli> as tStamp;
		interface Timer<TMilli> as Timer;
		interface Timer<TMilli> as DecayTimer;
	}
} implementation {
	
	enum{
		AGG_LEN = 2, //how many readings to we need to have
	};

	/*===========================
	*/
	typedef struct Sample
	{
		int _temperature;
		long int _time;
		double _valueV;
		bool _valid;
	} Sample;

	typedef struct Data
	{
		Sample _samples[10];
		unsigned int _size;
		bool _valid;
	} Data;

	Data nodeData[10];
	uint8_t nodeID;
	double e = 2.271828;
	long int timePassed = 0; //in milliseconds
	
	uint8_t firstNeighbor=1; // #0 is base
	/*==========================
	*/
	//how many neighbors do we have
	uint8_t totalNeighbors = NEIGHBOR_COUNT;
	//when aggergating the sensor readings from neighbors how many do we have
	uint8_t neighborCount = NEIGHBOR_COUNT - 1;
	
	//which sensor values are wanted by a neighboring node
	uint8_t valsWanted;
	//which node wanted the sensor values
	uint8_t whoWantsVals;

	//raw temperature , light readings and message number
	uint16_t temp,mNum;
	//converted temperature readings
	uint16_t cTemp;
	//my timestamp for current readign
	uint32_t myTime;
	//average temperature
	uint32_t tav;


	//flags for various operations
	bool busy = FALSE, sendTemps = FALSE, sendReqMsg = FALSE, me = FALSE;
	message_t reqMT, sensMT, repMT;
	//holder of recieved sensor readings
	SenseMsg received[AGG_LEN];
	//holds the average sensor readings for all nodes
	uint32_t av[2];

	
	event void Boot.booted()
	{
		call RadioControl.start();
		call DecayTimer.startPeriodic(DECAY_TIME_INTERVAL);
	}
	
	void printNodeData()
	{
		int i;
		int j;
		for(i=0; i<10; ++i)
		{
			printf("ID: %d, size: %d, valid: %d ", i, nodeData[i]._size, nodeData[i]._valid);
			for(j=0; j<10; ++j)
			{
				printf("Sample#%d, temp:%d, time:%d, valid:%d", j, nodeData[i]._samples[j]._temperature,
				nodeData[i]._samples[j]._time,
				nodeData[i]._samples[j]._valid);
			}
		}
	}

	void printValidity()
	{
		int i;
		for(i=0; i<10; ++i)
		{
			if(nodeData[i]._valid)
				printf("#%d valid\n", i);
			else
				printf("#%d not valid\n", i);
		}
	}
	
	event void DecayTimer.fired()
	{
		int j;
		int id;
		busy=TRUE;
		timePassed = call DecayTimer.getNow();
		
		if (DEBUG) printf("*Decaying values...at%d\n", timePassed);
		for(id=firstNeighbor; id<totalNeighbors+1; ++id)
		{
			if (DEBUG) printf("*id:%d\n", id);
			if(nodeData[id]._valid)
			{
				if (DEBUG) printf("*nodeData valid...\n");
				for(j=0; j< nodeData[id]._size; ++j)
				{
					if (DEBUG) printf("*j:%d...\n", j);
					if(nodeData[id]._samples[j]._valid)
					{
						int secondsPassed = (timePassed - nodeData[id]._samples[j]._time)/1024;
						nodeData[id]._samples[j]._valueV = nodeData[nodeID]._samples[j]._valueV * pow(e, DECAY_RATE*secondsPassed);
						nodeData[id]._samples[j]._time = timePassed;
						if(DEBUG) { printf("*Node#%d; Seconds passed: %d;\n", id, secondsPassed); }
					}
				}
			}
		}
		busy=FALSE;
	}	
	
	event void  RadioControl.startDone(error_t error)
	{
		if(error != SUCCESS)
			call RadioControl.start();
		else 
		{
			call Timer.startPeriodic(READ_FRQ);	
		}	
	}

	event void RadioControl.stopDone(error_t error){}

	event void SendReport.sendDone(message_t* msg, error_t err) 
	{
		busy = FALSE;
	}

	/**
		Simple comparison scheme which is to get the average sensor reading for all nodes
		then if the average is violating a threshold then our own violation is not localized
		otherwise it is
		When done send a report to the basestation denoted as 0
	*/
	void triggerAlarm()
	{
			printf("ALARM HAS BEEN TRIGGERED!\n");
	}

	Sample aggregateSamples(Sample samples[], long int time)
	{
		Sample tempSample;
		tempSample._time = time;
		tempSample._temperature = 0;
		tempSample._valid = TRUE;
		if (DEBUG) printf("Aggregating...\n");
		tempSample._valueV = samples[0]._valueV + samples[1]._valueV - (samples[0]._valueV * samples[1]._valueV);
		tempSample._valueV = tempSample._valueV + samples[2]._valueV - (tempSample._valueV * samples[2]._valueV);	
		
		if (tempSample._valueV > ALARM_THRESH_VH)
		{
			triggerAlarm();
		}
		
		return tempSample;
	}

	task void compareAgg()
	{
		int i = 0;
		int s; //index
		Sample tempSample;
		
		for(i = 0; i < totalNeighbors; ++i)
		{
			if(received[i].tVal > FIRST_TEMP_THRESH_TR)
			{
				nodeID = received[i].nId;
				
				printf("Neighbor # %u", nodeID);
				printf("; temperature = %u", received[i].tVal);
				printf("; timestamp= %ld\n", received[i].tStamp);
				//new sample: if there is an entry for this node, add a new one, else create first entry
				if (nodeData[nodeID]._valid)
				{
					s = nodeData[nodeID]._size;
					nodeData[nodeID]._size++;
				}
				else
				{
					nodeData[nodeID]._valid = TRUE;
					nodeData[nodeID]._size = 1;
					s = 0;
				}

				tempSample._temperature = received[i].tVal;
				tempSample._time = call Timer.getNow();
				tempSample._valid = TRUE;
				if (received[i].tVal > SECOND_TEMP_THRESHOLD_TH)
					tempSample._valueV = PH;
				else
					tempSample._valueV = PL;

				nodeData[nodeID]._samples[s] = tempSample;

				//aggregate samples
				if (nodeData[nodeID]._size == 3)
				{
					//aggregate and assign to sample[0]
					tempSample = aggregateSamples(nodeData[nodeID]._samples, call Timer.getNow());
					//reset samples except the first one
					for (i=1; i < 3; i++)
					{
						nodeData[nodeID]._samples[i]._valid = FALSE;
					}
					nodeData[nodeID]._size = 1;
					nodeData[nodeID]._samples[0] = tempSample;
				}
			}
		}
		printfflush();
	}

	/**
		For the aggregation stage when we recieve a sense message copy it to the array containing 
		neighbor readings increment the neighborcount by one to indicate we have recieved it 
		if we have all the readings from a neighbor start the comparison
		otherwise wait for another
	*/
	event message_t* RecSense.receive(message_t* msg, void* payload, uint8_t len)
	{
		memcpy(&received[neighborCount], ((SenseMsg*)payload), len);	
		neighborCount++;
		if(neighborCount == totalNeighbors)
		{
			neighborCount = 0;
			post compareAgg();
		}
		else
		{
			printf("Got a neighbor %u\n",neighborCount);
			printfflush();
		}
		return msg;
	}	
	
	/**
		I have recieved a request for sensor reading(s)
		get the values wanted and who wanted them 
		call for read raw and converted values
	*/
	event message_t* RecRmsg.receive(message_t* msg, void* payload, uint8_t len)
	{
		RequestMsg* rmsg = (RequestMsg*) payload;
		printf("Receiving RequestMsg\n");
		call Leds.led0On();
		valsWanted = rmsg->valsWanted;
		whoWantsVals = rmsg->reqNod;
		sendTemps = TRUE;
		busy = TRUE;
		call ReadTL.readRC();
		return msg;
	}

	event void SendSense.sendDone(message_t* msg, error_t err) 
	{
		if(&sensMT == msg)
		{
			busy = FALSE;
			sendTemps = FALSE;
			printf("Send sense msg done\n");
		}
	}

	event void SendReq.sendDone(message_t* msg, error_t err) 
	{
		if(&reqMT == msg)
			printf("Send temp request done. Waiting on reply\n");
	}	


	event void ReadTL.readRawDone(error_t result, uint16_t tmp, uint16_t lght){

	}
	
	/**
		When reading is done get time stamp and check if I am sending those readings to a neighboring node
		otherwise check if my readings are within their respective thresholds if not start the 
		aggergation 
	*/
	event void ReadTL.readConvertDone(error_t result,  uint16_t ct, uint16_t cl){
		cTemp = ct;
		myTime = call tStamp.get();

		if(sendTemps)
		{
			SenseMsg* sm = (SenseMsg*)call SensePkt.getPayload(&sensMT,sizeof(SenseMsg));
			sm->rawT = temp;
			sm->tVal = cTemp;
			sm->tStamp = myTime;
			sm->nId = TOS_NODE_ID;
			if(call SendSense.send(whoWantsVals,&sensMT, sizeof(SenseMsg)) == SUCCESS)
			{
				printf("Sending req\n");
				busy = FALSE;
				call Leds.led0Off();
			}
			else
			{
				printf("Did not send\n");
			}
			sendTemps = FALSE;
		}
		else 
		{
			RequestMsg* r = (RequestMsg*)call RecPkt.getPayload(&reqMT,sizeof(RequestMsg));
			r->reqNod = TOS_NODE_ID;
			r->valsWanted = Req_TL;
			if(call SendReq.send(AM_BROADCAST_ADDR,&reqMT,sizeof(RequestMsg)) == SUCCESS)
			{
				busy = TRUE;
				printf("Requesting Temps\n");
			}
			else
			{
				printf("Request failed\n");
			}
		printfflush();
		}
	}

	/**
		When reading is done get time stamp and check if I am sending those readings to a neighboring node
		otherwise start the aggergation 
	*/
	event void ReadTL.readRCDone(error_t result, uint16_t tmp, uint16_t ct,  uint16_t lght, uint16_t cl){
		temp = tmp;
		cTemp = ct;
		myTime = call tStamp.get();
		if(DEBUG)
		{
			printf("Converted temp = %u\n",ct);
			printf("My Time = %ld\n\n",myTime);
		}
		if(sendTemps)
		{
			SenseMsg* sm = (SenseMsg*)call SensePkt.getPayload(&sensMT,sizeof(SenseMsg));
			sm->rawT = temp;
			sm->tVal = cTemp;
			sm->tStamp = myTime;
			sm->nId = TOS_NODE_ID;
			if(call SendSense.send(whoWantsVals,&sensMT, sizeof(SenseMsg)) == SUCCESS)
			{
				printf("Sending req\n");
				busy = FALSE;
				call Leds.led0Off();
			}
			else
			{
				printf("Did not send\n");
			}
			sendTemps = FALSE;
		}
		else 
		{
			RequestMsg* r = (RequestMsg*)call RecPkt.getPayload(&reqMT,sizeof(RequestMsg));
			r->reqNod = TOS_NODE_ID;
			r->valsWanted = Req_TL;
			if(call SendReq.send(AM_BROADCAST_ADDR,&reqMT,sizeof(RequestMsg)) == SUCCESS)
			{
				busy = TRUE;
			}
			else
			{
				printf("Request failed\n");
			}
		printfflush();
		}
	}	

	event void Timer.fired()
	{
		if(busy)
		{
			return;
		} 
		else 
		{
			call ReadTL.readRC();	
		}
	}

}
