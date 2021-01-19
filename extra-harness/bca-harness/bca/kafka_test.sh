#!/bin/bash

for lc in "local"
do
	for prod in 4 #6 8  
	do
for i in 1 2 3
do
		mkdir -p /opt/output/results/kafka_2/${lc}-${prod}-producer-$i
		ruby /opt/bca/kafka_auto_${lc}.rb RF3_without_compression_producer /opt/output/results/kafka_2/${lc}-${prod}-producer-$i $prod > /opt/output/results/kafka_2/${lc}-${prod}-producer-$i/test.log 2>&1
		mkdir -p /opt/output/results/kafka_2/${lc}-${prod}-consumer-$i
		ruby /opt/bca/kafka_auto_${lc}.rb RF3_without_compression_consumer /opt/output/results/kafka_2/${lc}-${prod}-consumer-$i $prod --run-only > /opt/output/results/kafka_2/${lc}-${prod}-consumer-$i/test.log 2>&1
	done
done
done
