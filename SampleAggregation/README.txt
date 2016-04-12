README for SenseNodeAppC
Author/Contact: Bartosz Maj bmaj@cs.odu.edu

Description:

These are sensor nodes for the sensor reading aggregation

To make the application use the command: make iris install.0 mib520,/dev/ttyUSB0
Note:
-The number of neighbors to get reading from must be changed at line 44 of SenseNodeC if wanting to have more than 1 negihbor
  	which it is set at now due to me having only three motes two are nodes one is base station
-Basic printf usage for printing to screen results for more details of stages go through code and uncomment  	

Installation and running:
	base:
		make iris install,0 mib520,/dev/ttyUSB0
	node number n:
		make iris install,n mib520,/dev/ttyUSB0

	receive messages with:
		java net.tinyos.tools.PrintfClient -comm serial@/dev/ttyUSB1:iris

