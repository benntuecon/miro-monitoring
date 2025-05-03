import httpx
import json
import asyncio
import boto3
from pydantic import BaseModel
from glide import NodeAddress, GlideClusterClientConfiguration, GlideClusterClient


class Unit_info(BaseModel):
    price: int
    area: int
    id: int
    unit_number: str


def floor_filter(unit):
    return unit["filters"]["floor_12978"][0] > 11 and unit["price"] < 4000


async def get_client():
    addresses = [NodeAddress("miro-hmmqw4.serverless.usw1.cache.amazonaws.com", 6379)]
    config = GlideClusterClientConfiguration(addresses=addresses, use_tls=True)
    client = await GlideClusterClient.create(config)
    return client


async def track_units_and_notify(units):
    # Get Valkey client
    valkey_client = await get_client()

    # Get SNS client
    sns = boto3.client("sns")
    topic_arn = "arn:aws:sns:us-west-1:398888507385:miro-alerts"  # Replace with your actual SNS topic ARN

    # Get the current set of unit IDs from Valkey
    seen_unit_ids_str = await valkey_client.get("seen_unit_ids")
    seen_unit_ids = set(json.loads(seen_unit_ids_str)) if seen_unit_ids_str else set()

    # Extract current unit IDs from the fetched units
    current_unit_ids = {unit.id for unit in units}

    # Find new units
    new_unit_ids = current_unit_ids - seen_unit_ids
    new_units = [unit for unit in units if unit.id in new_unit_ids]

    # If there are new units, notify via SNS
    if new_units:
        # Format the message
        message = "New units available:\n\n"
        for unit in new_units:
            message += (
                f"Unit {unit.unit_number}: ${unit.price}/month, {unit.area} sq ft\n"
            )

        # Send the notification
        try:
            sns.publish(
                TopicArn=topic_arn, Subject="New Available Units Alert", Message=message
            )
            print(f"Notification sent for {len(new_units)} new units")
        except Exception as e:
            print(f"Failed to send SNS notification: {e}")

    # Update the set of seen unit IDs in Valkey
    await valkey_client.set("seen_unit_ids", json.dumps(list(current_unit_ids)))

    # Close the client
    await valkey_client.close()

    return new_units


async def async_handler(event, context):
    client = httpx.Client()
    ret = client.get("https://sightmap.com/app/api/v1/yjp2k0q9pxl/sightmaps/23140")
    ret = ret.json()
    units = ret["data"]["units"]
    feasible_units = [unit for unit in units if floor_filter(unit)]
    print(f"Found {len(feasible_units)} feasible units")

    info_list = [Unit_info(**x) for x in feasible_units]

    # Track units and send notifications if there are new ones
    new_units = await track_units_and_notify(info_list)
    print(f"Detected {len(new_units)} new units")

    return [x.model_dump() for x in info_list]


def handler(event, context):
    """Lambda handler function that calls the async handler"""
    return asyncio.run(async_handler(event, context))


if __name__ == "__main__":
    print(asyncio.run(async_handler(None, None)))
