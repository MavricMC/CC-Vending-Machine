itemList = {
    {"Bud light", "minecraft:potion", 5, false, "1"}, --Name in search, item name to pull from storage, unit cost, can edit quanity---min and max at end if quanity can be editited (true)-- (Max must be greater than min and teh same length or more. Both must be greater than 1)
    {"Ford F105", "minecraft:oak_boat", 15, false, "1"}, --Default quanity must be a valid quality (Works with tonumber() and greatre than 0) --Must be string, not number
    {"Cake", "minecraft:cake", 10, true, "1", 1, 15},
    {"Cookie", "minecraft:cookie", 1, true, "5", 1, 64},
    {"Milk", "minecraft:milk_bucket", 1, false, "2"}
}
