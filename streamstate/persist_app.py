from pyspark.sql import SparkSession, DataFrame
from typing import List, Dict, Tuple
import sys
from streamstate.utils import map_avro_to_spark_schema, get_folder_location
from streamstate.generic_wrapper import (
    file_wrapper,
    write_console,
    kafka_wrapper,
    write_wrapper,
    set_cassandra,
    write_cassandra,
    write_kafka,
    write_parquet,
)
import json
from streamstate.structs import OutputStruct, KafkaStruct, InputStruct
import marshmallow_dataclass


def persist_topic(
    app_name: str,
    input: InputStruct,
    kafka: KafkaStruct,
    output: OutputStruct,
):
    spark = SparkSession.builder.appName(app_name).getOrCreate()
    df = kafka_wrapper(app_name, kafka.brokers, lambda dfs: dfs[0], [input], spark)
    write_wrapper(
        df,
        output,
        lambda df: write_parquet(df, get_folder_location(app_name, input.topic)),
    )


# examples
# mode = "append"
# schema_struct =
#     {"topic": "topic1",
#         "schema": {
#             "fields": [
#                 {"name": "first_name", "type": "string"},
#                 {"name": "last_name", "type": "string"},
#             ]
#         },
#     }
#
if __name__ == "__main__":
    [app_name, output_struct, kafka_struct, input_struct] = sys.argv

    output_schema = marshmallow_dataclass.class_schema(OutputStruct)()
    output_info = output_schema.load(json.loads(output_struct))
    kafka_schema = marshmallow_dataclass.class_schema(KafkaStruct)()
    kafka_info = kafka_schema.load(json.loads(kafka_struct))
    input_schema = marshmallow_dataclass.class_schema(InputStruct)()
    input_info = input_schema.load(json.loads(input_struct))
    persist_topic(
        app_name,
        input_info,
        kafka_info,
        output_info,
    )