import httpx
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


def handler(_, *arg, **kwarg):
    client = httpx.Client()
    ret = client.get("https://sightmap.com/app/api/v1/yjp2k0q9pxl/sightmaps/23140")
    ret = ret.json()
    units = ret["data"]["units"]
    feasible_units = [unit for unit in units if floor_filter(unit)]
    print(len(feasible_units))

    info_list = [Unit_info(**x) for x in feasible_units]
    return [x.model_dump() for x in info_list]


if __name__ == "__main__":
    print(handler(None))
