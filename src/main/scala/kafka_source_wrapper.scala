/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// scalastyle:off println
package dhstest
import org.apache.log4j.{Level, Logger}
import org.apache.spark.sql.streaming.Trigger
import org.apache.spark.internal.Logging
import org.apache.spark.sql.types.{IntegerType, StringType, StructField, StructType}
import org.apache.spark.sql.functions.{from_json, col}
import org.apache.kafka.clients.consumer.ConsumerConfig
import org.apache.kafka.common.serialization.StringDeserializer

import org.apache.spark.SparkConf
import org.apache.spark.streaming._
import org.apache.spark.streaming.kafka010._
import org.apache.spark.sql.SparkSession
/**
 * Consumes messages from one or more topics in Kafka and does wordcount.
 * Usage: DirectKafkaWordCount <brokers> <topics>
 *   <brokers> is a list of one or more Kafka brokers
 *   <groupId> is a consumer group name to consume from topics
 *   <topics> is a list of one or more kafka topics to consume from
 *
 * Example:
 *    $ bin/run-example streaming.DirectKafkaWordCount broker1-host:port,broker2-host:port \
 *    consumer-group topic1,topic2
 */
object KafkaSourceWrapper {
  def main(args: Array[String]): Unit = {
    if (args.length < 4) {
      System.err.println(s"""
        |Usage: KafkaSourceWrapper <brokers> <groupId> <topics>
        |  <brokers> is a list of one or more Kafka brokers
        |  <groupId> is a consumer group name to consume from topics
        |  <topics> is a list of one or more kafka topics to consume from
        |  <outputMode> one of Complete, Append, Update
        |  <sink> file output for kafka sink
        |  <checkpoint> file output for streaming checkpoint
        """.stripMargin)
      System.exit(1)
    }

    StreamingExamples.setStreamingLogLevels()

    val Array(brokers, groupId, topics, outputMode, sink, checkpoint) = args
    val spark = SparkSession
      .builder
      .appName("DirectKafkaWordCount")
      .getOrCreate()
    val schema = StructType(
      List(
        StructField("id", IntegerType, true),
        StructField("first_name", StringType, true),
        StructField("last_name", StringType, true),
        StructField("email", StringType, true),
        StructField("gender", StringType, true),
        StructField("ip_address", StringType, true),
      )
    )
    val dfs=topics.split(",").map(topic=>spark
      .readStream
      .format("kafka")
      .option("kafka.bootstrap.servers", brokers)
      .option("subscribe", topic)
      .load()
      .selectExpr("CAST(value AS STRING) as json")
      .select( from_json(col("json"), schema=schema).as("data"))
      .select("data.*"))
    
    val result=Custom.process(dfs)

    //so we keep a record in case we need to replay history
    dfs.foreach(df=>df.writeStream
      .format("json")  // can be "orc", "json", "csv", etc.
      .outputMode("Append")  
      .option("checkpointLocation", checkpoint)
      .trigger(Trigger.ProcessingTime("2 seconds")) //only write every so often   
      .option("path", sink)
      .start()
    )

    result.writeStream
      .format("console")
      .outputMode(outputMode)
      .option("truncate","false")
      .option("checkpointLocation", checkpoint)
      .start()
      .awaitTermination()    
    
  }
}
