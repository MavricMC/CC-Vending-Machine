--Vending Machine--

local vers = "0.1"

--Made by Mavric--
--How to setup is on my youtube channel--
--Code on https://github.com/MavricMC/CC-Vending-Machine-- Need to update

os.pullEvent = os.pullEventRaw --Prevent program termination
os.loadAPI("/vend/items.lua") --Long list of products is stored seperate
os.loadAPI("/vend/json.lua")

--Settings--
local atm = "vend_1"
local bankSide = "modem_0"
local drive = "bottom"
local server = 0 --Server id
local logFile = "/vend/log"
local backgroundColor = colors.black
local chests = {"minecraft:chest_0"}
local junk = "minecraft:chest_1" --Given that it has to empty 2 barrels each payment, a chest with a hopper to a dropper is reccomended. 9 slot dropper from ATM would be too small--
local output = "minecraft:barrel_0"
local buffer = "minecraft:barrel_1" --Buffer must have the same amount of storage slots as the ouput. (Or less) Easy to just use the same storage block for both
local salesTax = 0.15 --0.15 = 15% --math.celi used to display most totals, bank charged full float. Makes display short and price is still 2dp at payment
local addTax = false --false = removes sales tax from price of the item to calculate subtotal, true = adds the sales tax onto the price of the item to get total (USA)
local bankTimeout = 10 --How many seconds the bank function will wait before timing out
local searchResultsLength = 10
local searchMaxLength = 18
local searchMaxExtra = 4 --Extra max length added to suggestions vs search
local mainButtons = {
    {"Clear", 2, 16, colors.red, colors.white}, --Text, lop left x and y, background color, text color
    {"Pay", 46, 16, colors.green, colors.white}
}

local configButtons = { --Displayed only in config
    {"Delete", 10, 16, colors.gray, colors.white}, --Simple button to escape config no matter the situation --Deletes item if its in order because the config could be invalid
    {"Enter", 19, 16, colors.blue, colors.white}
}

--Program wide variables--
local searchText = ""
local searchY = 0
local searchLength = 0
local typedLen = 0
local searchResults = {} --Indexs for items in main list
local order = {}
local editing = {} --Index for the item in the main list and stored modified values
local mode = 1 --1 search, 2 modify item, 3 payment
local lastMode = 1 --Stores whether the user was editing or searching when they clicked history or payment
local total = 0 --Total calculated price
local id = 0 --Id of card inserted
local pin = "" --Current entered pin
local isPin = false --In pin entering stage
local orderY = 1 --Which order item is displayed at the top

local junk_ = peripheral.wrap(junk)
local output_ = peripheral.wrap(output)
local buffer_ = peripheral.wrap(buffer)

if buffer_.size() > output_.size() then
    error("Buffer has more slots than output")
end

--Storage functions--
function getStored(name)
    local count = 0
    for _, v in pairs(chests) do
        local chest = peripheral.wrap(v)
        for _, item in pairs(chest.list()) do
            if item.name == name then
                count = count + item.count
            end
        end
    end
    return count
end

function flush(to, from, timeout)
    local inFrom = from.list()
    for k, v in pairs(inFrom) do
        local count = 0
        if timeout then
            local time = 0
            while count < v.count and time < 50 do --5 second timeout till it gives up
                count = count + to.pullItems(peripheral.getName(from), k)
                time = time + 1
                sleep(0.1)
            end
        else
            count = to.pullItems(peripheral.getName(from), k) --Without timeout, only try once
        end
        if count ~= v.count then
            --printError("Failed flush ".. peripheral.getName(from).. " to ".. peripheral.getName(to))--Error is useful for debugging but is unhelpful and unsecure for users to see
            --sleep(3)
            return false
        end
    end

    return true
end

function getItem(name, count)
    local added = 0
    for _, v in pairs(chests) do
        local chest = peripheral.wrap(v)
        local inChest = chest.list()
        for k, item in pairs(inChest) do
            if item.name == name then
                local moved = chest.pushItems(buffer, k, (count - added))
                added = added + moved
                if added > count then --Somehow to much
                    return false, "Buffered too much ".. name
                elseif added == count then --Reached the goal so no points continuing
                    return true
                end
            end
        end
    end

    return false, "Not enough ".. name
end

function cleanBuffer()
    for _, v in pairs(chests) do
        chest = peripheral.wrap(v)
        flush(chest, buffer_, false) --Flush worked, so items in buffer are only products, to return to chest, no timeout cause trying lots of chests--
    end
end

function toBuffer()
    local result = flush(junk_, buffer_, true)
    if result then
        for _, v in pairs(order) do
            local result2, error = getItem(v[2], tonumber(v[5]))
            if not result2 then
                cleanBuffer()
                return false, error
            end
        end

        return true
    else
        return false, "Failed to flush buffer to junk"
    end
end

--Bank functions--
function balance(account, ATM, pin)
    local msg = {"bal", account, ATM, pin}
    rednet.send(server, msg, "banking")
    local send, mes, pro = rednet.receive("banking", bankTimeout)
    if not send then
        return false, "timeout"
    else
        if mes[1] == "balR" then
            return mes[2], mes[3]
        end
    end
    return false, "oof"
end

function deposit(account, amount, ATM, pin)
    local msg = {"dep", account, amount, ATM, pin}
    rednet.send(server, msg, "banking")
    local send, mes, pro = rednet.receive("banking", bankTimeout)
    if not send then
        return false, "timeout"
    else
        if mes[1] == "depR" then
            return mes[2], mes[3]
        end
    end
    return false, "oof"
end

function withdraw(account, amount, ATM, pin)
    local msg = {"wit", account, amount, ATM, pin}
    rednet.send(server, msg, "banking")
    local send, mes, pro = rednet.receive("banking", bankTimeout)
    if not send then
        return false, "timeout"
    else
        if mes[1] == "witR" then
            return mes[2], mes[3], amount
        end
    end
    return false, "oof"
end

function transfer(account, account2, amount, ATM, pin)
    local msg = {"tra", account, account2, amount, ATM, pin}
    rednet.send(server, msg, "banking")
    local send, mes, pro = rednet.receive("banking", bankTimeout)
    if not send then
        return false, "timeout"
    else
        if mes[1] == "traR" then
            return mes[2], mes[3]
        end
    end
    return false, "oof"
end

function create(account, ATM, pin)
    local msg = {"cre", account, ATM, pin}
    rednet.send(server, msg, "banking")
    local send, mes, pro = rednet.receive("banking", bankTimeout)
    if not send then
        return false, "timeout"
    else
        if mes[1] == "creR" then
            return mes[2], mes[3]
        end
    end
    return false, "oof"
end

--Other functions--
function unlinkArray(array)
    local output = {}
    for k, v in pairs(array) do
        if (type(v) == "table") then
            output[k] = unlinkArray(v)
        else
            output[k] = v
        end
    end
    return output
end

function lengthCheck(text, length, trimEnd)
    local textLength = string.len(text)
    if textLength > length then
        if trimEnd then
            return true, string.sub(text, 1, length), textLength - length--Trim end of the string
        else
            return true, string.sub(text, textLength - length + 1, textLength), textLength - length --Trim start of the string
        end
    end
    return false, text, 0
end

function writeCenter(text, y)
    term.setCursorPos(math.floor(26 - (string.len(text) / 2)), y)
    term.write(text)
end

function clearScreen()
    term.setBackgroundColor(backgroundColor)
    term.setTextColor(colors.yellow)
    term.clear()
    term.setCursorPos(1, 1)
    term.write("Vending Machine ".. vers)
    term.setCursorPos(1, 19)
    term.setTextColor(colors.lightGray)
    term.write("Made By Mavric, Please Report Bugs")
end

function drawX()
    term.setBackgroundColor(colors.red)
    term.setTextColor(colors.white)
    term.setCursorPos(49, 17)
    term.write("X")
end

function drawButton(buttonArray)
    term.setBackgroundColor(buttonArray[4])
    term.setTextColor(buttonArray[4])
    term.setCursorPos(buttonArray[2], buttonArray[3])
    term.write("OO".. buttonArray[1])
 
    term.setCursorPos(buttonArray[2], buttonArray[3] + 1)
    term.write("O")
    term.setTextColor(buttonArray[5])
    term.write(buttonArray[1])
    term.setTextColor(buttonArray[4])
    term.write("O")
 
    term.setCursorPos(buttonArray[2], buttonArray[3] + 2)
    term.write("OO".. buttonArray[1])
end

function drawButtons(buttons)
    for _, v in pairs(buttons) do
        drawButton(v)
    end
end

function drawOrderList()
    total = 0
    term.setTextColor(colors.white)
    for i = 1, #order do
        local k = i - orderY + 1 --Used a lot
        local price = ""
        local quantity = order[i][5]
        if order[i][5] == "" then
            quantity = "0"
        end
        if addTax then
            price = string.format("$%.02f", order[i][3] * quantity * (1 + salesTax))
            total = total + order[i][3] * quantity * (1 + salesTax)
        else
            price = string.format("$%.02f", order[i][3] * quantity)
            total = total + order[i][3] * quantity
        end

        if k > 0 and k < 8 then
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
            term.setCursorPos(28, 2 * k)
            term.write("\7")

            term.setBackgroundColor(backgroundColor)
            local toLong, results = lengthCheck(order[i][1], 20, true)
            term.write(results)
            if toLong then
                term.setTextColor(colors.red)
                term.write("\16")
            end
            term.setTextColor(colors.yellow)
            term.setCursorPos(29, 2 * k + 1)
            term.write("#:")
            term.setTextColor(colors.white)
            term.write(order[i][5])
            
            term.setTextColor(colors.yellow)
            term.setCursorPos(49 - string.len(price), 2 * k + 1)
            term.write(price)
            
            term.setBackgroundColor(colors.red)
            term.setTextColor(colors.white)
            term.setCursorPos(50, 2 * k)
            term.write("X")
        end
    end

    local subtotal = string.format("$%.02f", total * (1 - salesTax))
    local tax = string.format("$%.02f", total * salesTax)
    local totalPrice = string.format("$%.02f", total)
    term.setBackgroundColor(backgroundColor)
    term.setTextColor(colors.yellow)
    term.setCursorPos(27, 16)
    term.write("Subtotal:")
    term.setTextColor(colors.white)
    term.write(subtotal)

    term.setTextColor(colors.yellow)
    term.setCursorPos(27, 17)
    term.write("Tax:")
    term.setTextColor(colors.white)
    term.write(tax)

    term.setTextColor(colors.yellow)
    term.setCursorPos(27, 18)
    term.write("Total:")
    term.setTextColor(colors.white)
    term.write(totalPrice)

    term.setTextColor(colors.yellow)
    term.setCursorPos(27, 14)
    term.write("-")
    term.setTextColor(colors.white)
    term.setCursorPos(27, 13)
    term.write("\30")
    term.setCursorPos(27, 15)
    term.write("\31")
end

function drawConfig()
    local toLong, results = lengthCheck(editing[2][1], searchMaxLength, true)
    drawButtons(configButtons)

    term.setBackgroundColor(backgroundColor)
    term.setTextColor(colors.yellow)
    term.setCursorPos(2, 2)
    term.write("Item: ")
    term.setTextColor(colors.white)
    term.write(results)
    if toLong then
        term.setTextColor(colors.red)
        term.write("\16")
    end

    local price = ""
    if addTax then
        price = string.format("$%d", editing[2][3] * (1 + salesTax))
    else
        price = string.format("$%d", editing[2][3])
    end

    term.setTextColor(colors.yellow)
    term.setCursorPos(2, 3)
    term.write("Price:")
    term.setTextColor(colors.white)
    term.write(price)

    local totalPrice = ""
    local quantity = editing[2][5]
    if editing[2][5] == "" then
        quantity = "0"
    end
    if addTax then
        totalPrice = string.format("$%.02f", editing[2][3] * quantity * (1 + salesTax))
    else
        totalPrice = string.format("$%.02f", editing[2][3] * quantity)
    end
    
    term.setTextColor(colors.yellow)
    term.setCursorPos(2, 14)
    term.write("Total:")
    term.setTextColor(colors.white)
    term.write(totalPrice)

    if editing[2][4] then --Quantity editable
        local limitLen = string.len(editing[2][7])

        term.setTextColor(colors.yellow)
        term.setCursorPos(2, 5)
        term.write("Quantity")

        term.setCursorPos(2, 6) --Draw indicator
        term.write("#:")

        term.setBackgroundColor(colors.gray) --Draw input box
        term.setTextColor(colors.white)
        term.write(editing[2][5])
        term.setTextColor(colors.gray)
        term.write(string.sub("                ", string.len(editing[2][5]), limitLen)) --Draw rest not ten up by current input

        term.setTextColor(colors.white)
        term.setCursorPos(string.len(editing[2][5]) + 4, 6)
        term.setCursorBlink(true)
    else
        term.setTextColor(colors.yellow)
        term.setCursorPos(2, 4)
        term.write("Quantity:")
        term.setTextColor(colors.white)
        term.write(editing[2][5])
        term.setCursorBlink(false)
    end
end

function drawPayment(insert, x)
    clearScreen()
    local pic = paintutils.loadImage("/vend/MPNLogo.nfp")
    paintutils.drawImage(pic, 18, 3)
    if (insert) then
        term.setBackgroundColor(backgroundColor)
        term.setTextColor(colors.white)
        writeCenter("Please insert card", 13) 
    end
    if (x) then
        term.setBackgroundColor(backgroundColor)
        term.setTextColor(colors.white)
        local cost = string.format("$%.02f", total)
        writeCenter(cost, 12) --Drawing x means not in an response display
        drawX()
    end
end

function drawPin(ID)
    drawPayment(false, true)
    term.setBackgroundColor(backgroundColor)
    term.setTextColor(colors.yellow)
    term.setCursorPos(1, 2)
    term.write("ID:")
    term.setTextColor(colors.white)
    term.write(ID)

    term.setCursorPos(20, 13)
    term.setTextColor(colors.white)
    term.write("PIN: ")
    term.setCursorBlink(true)
end

function checkX(x, y)
    if x == 49 and y == 17 then
        return true
    else
        return false
    end
end

function drawSearch(resChange)
    local toLong, results, hidden = lengthCheck(searchText, searchMaxLength, false)

    if resChange < 2 then
        typedLen = string.len(searchText)
    end
    if typedLen > 0 then
        if resChange == 0 then
            searchResults = {}
            for k, v in pairs(items.itemList) do
                if string.lower(string.sub(v[1], 1, typedLen)) ==  string.lower(searchText) then
                    table.insert(searchResults, k)
                end
            end
            searchLength = #searchResults
        elseif resChange == 1 then --check in old search results istead of whole list
            local recycle = searchResults
            searchResults = {}
            for _, v in pairs(recycle) do
                if string.lower(string.sub(items.itemList[v][1], 1, typedLen)) ==  string.lower(searchText) then
                    table.insert(searchResults, v)
                end
            end
            searchLength = #searchResults
        end

        term.setTextColor(colors.white)
        local overflowOffset = searchY - searchResultsLength
        local tempLength = searchResultsLength
        if overflowOffset < 0 then
            overflowOffset = 0
        end
        if searchLength < searchResultsLength then
            tempLength = searchLength
        end
        for k = 1 + overflowOffset, tempLength + overflowOffset, 1 do
            if k == searchY then
                term.setBackgroundColor(colors.gray)
            else
                term.setBackgroundColor(backgroundColor)
            end

            term.setCursorPos(4, 3 + (k - overflowOffset))
            local toLongAlt, resultsAlt = lengthCheck(items.itemList[searchResults[k]][1], searchMaxLength + searchMaxExtra, true)
            if toLongAlt and toLong then
                resultsAlt = string.sub(items.itemList[searchResults[k]][1], hidden + 1, string.len(items.itemList[searchResults[k]][1]))
                toLongAlt, resultsAlt = lengthCheck(resultsAlt, searchMaxLength + searchMaxExtra, true)
            end
            term.write(resultsAlt)
            if toLongAlt then
                term.setTextColor(colors.red)
                term.write("\16")
                term.setTextColor(colors.white)
            end
        end

        if searchY < searchLength and searchLength > searchResultsLength then
            term.setBackgroundColor(backgroundColor)
            term.setTextColor(colors.red)
            term.setCursorPos(4, 4 + searchResultsLength)
            term.write("\31")
        end
    else
        searchLength = 0
    end

    term.setBackgroundColor(backgroundColor)
    term.setTextColor(colors.yellow)
    term.setCursorPos(2, 2)
    term.write("Search and select an item")

    term.setCursorPos(2, 3)
    if toLong then
        term.write(">")
        term.setTextColor(colors.red)
        term.write("\17")
    else
        term.write("> ")
    end

    term.setTextColor(colors.white)
    term.write(results)
end

function checkSearch(searched)
    for k, v in pairs(items.itemList) do
        if string.lower(v[1]) ==  string.lower(searched) then
            return true, k
        end
    end
    return false
end

--Start Program
rednet.open(bankSide)
term.setCursorBlink(true)
clearScreen()
drawButtons(mainButtons)
drawOrderList()
drawSearch(2)

while true do
    local event = {os.pullEvent()}
    if event[1] == "terminate" then
        if (redstone.getInput("right")) then
            return
        end
    elseif event[1] == "char" then
        if mode == 1 then
            searchY = 0
            searchText = searchText.. event[2]
            clearScreen()
            drawButtons(mainButtons)
            drawOrderList()
            if typedLen > 0 then
                drawSearch(1) --Adding letters cant widen the scope of the search
            else
                drawSearch(0)
            end
        elseif mode == 2 then
            if tonumber(event[2]) then
                if editing[2][4] then --Quantity editable
                    temp = editing[2][5].. event[2]
                    if string.len(temp) <= string.len(editing[2][7]) then --Check its nto too long
                        editing[2][5] = temp
                        clearScreen()
                        drawButtons(mainButtons)
                        drawOrderList()
                        drawConfig()
                    end
                end
            end
        elseif mode == 3 and isPin then
            if tonumber(event[2]) then
                if string.len(pin) < 5 then
                    pin = pin.. event[2]
                    term.setBackgroundColor(backgroundColor)
                    term.setTextColor(colors.white)
                    term.setCursorPos(24 + string.len(pin), 13)
                    term.write("*")
                end
            end
        end
    elseif event[1] == "key" then
        if mode == 1 then
            if event[2] == 259 then --backspace
                searchText = string.sub(searchText, 1, string.len(searchText) - 1)
                searchY = 0
                clearScreen()
                drawButtons(mainButtons)
                drawOrderList()
                drawSearch(0)
            elseif event[2] == 257 or event[2] == 335 then --enter
                if typedLen > 0 then
                    local success, searchIndex = checkSearch(searchText)
                    if success then
                        mode = 2
                        editing[1] = true --Singify that user is editing item not yet in order
                        editing[2] = {}
                        for _, v in pairs(items.itemList[searchIndex]) do
                           table.insert(editing[2], v)
                        end
                        
                        clearScreen()
                        drawButtons(mainButtons)
                        drawOrderList()
                        drawConfig()
                    end
                end
            elseif event[2] == 258 then --tab
                if searchY > 0 then
                    searchText = items.itemList[searchResults[searchY]][1]
                    searchY = 0
                    clearScreen()
                    drawButtons(mainButtons)
                    drawOrderList()
                    drawSearch(1)--must be in search results
                end
            elseif event[2] == 265 then --up arrow
                if searchY > 1 then
                    searchY = searchY - 1
                else
                    searchY = searchLength
                end
                clearScreen()
                drawButtons(mainButtons)
                drawOrderList()
                drawSearch(2)
            elseif event[2] == 264 then --down arrow
                if searchY < searchLength then
                    searchY = searchY + 1
                else
                    searchY = 1
                end
                clearScreen()
                drawButtons(mainButtons)
                drawOrderList()
                drawSearch(2)
            end
        elseif mode == 2 then
            if event[2] == 259 then --backspace
                if editing[2][4] then --Quantity editable
                    if string.len(editing[2][5]) > 0 then
                        editing[2][5] = string.sub(editing[2][5], 1, string.len(editing[2][5]) - 1)
                        clearScreen()
                        drawButtons(mainButtons)
                        drawOrderList()
                        drawConfig()
                    else
                        if editing[1] then --Quanity entered doesnt matter if item not in list
                            editing = {}
                            mode = 1
                            term.setCursorBlink(true)
                            clearScreen()
                            drawButtons(mainButtons)
                            drawOrderList()
                            drawSearch(0)
                        end
                    end
                else
                    editing = {} --If no quantity edit, then quantity always valid
                    mode = 1
                    term.setCursorBlink(true)
                    clearScreen()
                    drawButtons(mainButtons)
                    drawOrderList()
                    drawSearch(0)
                end
            elseif event[2] == 257 or event[2] == 335 then --enter
                local canAdd = false
                if editing[2][4] then
                    if editing[2][5] ~= "" then --prevent nil error with tonumber
                        if tonumber(editing[2][5]) <= editing[2][7] and tonumber(editing[2][5]) >= editing[2][6] then --In range set by min and max (Inclusive)
                            canAdd = true
                        end
                    end
                else
                    canAdd = true --Cant edit quantity
                end

                if canAdd then
                    if editing[1] then --New input
                        table.insert(order, editing[2])
                    end
                    editing = {}
                    mode = 1
                    term.setCursorBlink(true)
                    searchText = ""
                    searchY = 0
                    clearScreen()
                    drawButtons(mainButtons)
                    drawOrderList()
                    drawSearch(0)
                end
            end
        elseif mode == 3 and isPin then
            if event[2] == 259 then --backspace
                if string.len(pin) > 0 then
                    pin = string.sub(pin, 1, string.len(pin) - 1)
                    term.setBackgroundColor(backgroundColor)
                    term.setTextColor(colors.white)
                    term.setCursorPos(20, 13)
                    term.clearLine()
                    term.write("PIN: ".. string.sub("****", 1, string.len(pin)))
                end
            elseif event[2] == 257 or event[2] == 335 then --enter
                if string.len(pin) == 5 then
                    drawPayment(false, false)
                    term.setCursorBlink(false)
                    local payText = string.format("Processing transaction: $%.02f", total)
                    term.setBackgroundColor(backgroundColor)
                    term.setTextColor(colors.white)
                    writeCenter(payText, 13)

                    local suc = flush(junk_, output_, true)
                    local res = "Default"
                    if suc then
                        suc, res = toBuffer()
                        if suc then
                            suc, res = withdraw(id, total, atm, pin)
                            if suc then
                                disk.setLabel(drive, "$".. tostring(res))
                                flush(output_, buffer_, true) --If the user fills the output after we flush it, thats their fault
                            else
                                cleanBuffer()
                            end
                        end
                    else
                        res = "Failed to flush output to junk"
                    end
                    
                    disk.eject(drive)
                    drawPayment(false, false)
                    --print()
                    local logArray =  {{ date = os.date("*t"), vendVersion = vers, server = server, card = id, total = total, location = atm, result = suc, response = res, salesTax = salesTax, addTax = addTax}}
                    for k, v in pairs(order) do --Reconstruct the items with the editable data from the order
                        table.insert(logArray,  unlinkArray(v))
                        --printError(logArray[k + 1][1])
                    end

                    --sleep(3)
                    local logLine = json.encode(logArray)
                    local log = fs.open(logFile, "a")
                    log.writeLine(logLine)
                    log.close()

                    if (suc) then
                        ---Move from buffer to output---
                        payText = string.format("Transaction authorised: $%.02f", total)
                        term.setBackgroundColor(backgroundColor)
                        term.setTextColor(colors.white)
                        writeCenter(payText, 13)
                        mode = 1
                        sleep(3)

                        term.setCursorBlink(true)
                        order = {}
                        orderY = 1
                        clearScreen()
                        drawButtons(mainButtons)
                        drawOrderList()
                        drawSearch(2)
                    else
                        ---Move from buffer back to storage---
                        term.setBackgroundColor(backgroundColor)
                        term.setTextColor(colors.white)
                        writeCenter("Transaction error: ".. res, 13)
                        id = 0
                        pin = ""
                        isPin = false
                        sleep(3)

                        drawPayment(true, true)
                    end
                end
            end
        end
    elseif event[1] == "mouse_click" then
        if mode == 3 then
            if (checkX(event[3], event[4])) then
                disk.eject(drive)
                term.setCursorBlink(false)
                drawPayment(false, false)
                local payText = string.format("Transaction cancelled: $%.02f", total)
                term.setBackgroundColor(backgroundColor)
                term.setTextColor(colors.white)
                writeCenter(payText, 13)
                mode = lastMode
                sleep(3)
                term.setCursorBlink(true)
                if mode == 1 then
                    clearScreen()
                    drawButtons(mainButtons)
                    drawOrderList()
                    drawSearch(2)
                else
                    clearScreen()
                    drawButtons(mainButtons)
                    drawOrderList()
                    drawConfig()
                end
            end
        else
            if mode == 1 or mode == 2 then
                if event[3] == 27 and event[4] == 13 then --Order up
                    if orderY > 1 then
                        orderY = orderY - 1
                        if mode == 1 then
                            clearScreen()
                            drawButtons(mainButtons)
                            drawOrderList()
                            drawSearch(2)
                        elseif mode == 2 then
                            clearScreen()
                            drawButtons(mainButtons)
                            drawOrderList()
                            drawConfig()
                        end
                    end
                elseif event[3] == 27 and event[4] == 15 then --Order down
                    if (#order - orderY) > 6 then
                        orderY = orderY + 1
                        if mode == 1 then
                            clearScreen()
                            drawButtons(mainButtons)
                            drawOrderList()
                            drawSearch(2)
                        elseif mode == 2 then
                            clearScreen()
                            drawButtons(mainButtons)
                            drawOrderList()
                            drawConfig()
                        end
                    end
                end

                local endNum = #order
                if endNum - orderY > 6 then
                    endNum = orderY + 6
                end
                for i = orderY, endNum do
                    if event[4] == 2 * (i - orderY + 1) then
                        if event[3] == 28 then
                            mode = 2
                            editing[1] = false --Signify that the user is editing an item already in order
                            editing[2] = order[i]
                            editing[3] = i
                            
                            clearScreen()
                            drawButtons(mainButtons)
                            drawOrderList()
                            drawConfig()
                        elseif event[3] == 50 then
                            if orderY > 1 then
                                if endNum == #order then
                                    orderY = orderY - 1 --Scroll up if removing last item and currently scrolled down
                                end
                            end
                            if editing == order[i] then --User deleted item currently being edited
                                table.remove(order, i)
                                editing = {}
                                mode = 1
                                term.setCursorBlink(true)
                                clearScreen()
                                drawButtons(mainButtons)
                                drawOrderList()
                                drawSearch(0)
                            else
                                table.remove(order, i)
                                clearScreen()
                                drawButtons(mainButtons)
                                drawOrderList()
                                drawSearch(2)
                            end
                        end
                    end
                end
            end

            if mode == 2 then
                for _, v in pairs(configButtons) do
                    if event[3] >= v[2] and event[3] < (v[2] + string.len(v[1]) + 2) and event[4] >= v[3] and event[4] < (v[3] + 3) then
                        if v[1] == "Delete" then --Delete config
                            if not editing[1] then --Item in order
                                table.remove(order, editing[3]) --Deleting item being edited if in order
                            end
                            editing = {}
                            mode = 1
                            term.setCursorBlink(true)
                            clearScreen()
                            drawButtons(mainButtons)
                            drawOrderList()
                            drawSearch(0)
                        elseif v[1] == "Enter" then
                            local canAdd = false
                            if editing[2][4] then
                                if editing[2][5] ~= "" then --prevent nil error with tonumber
                                    if tonumber(editing[2][5]) <= editing[2][7] and tonumber(editing[2][5]) >= editing[2][6] then --In range set by min and max (Inclusive)
                                        canAdd = true
                                    end
                                end
                            else
                                canAdd = true --Cant edit quantity
                            end

                            if canAdd then
                                if editing[1] then --New input
                                    table.insert(order, editing[2])
                                end
                                editing = {}
                                mode = 1
                                term.setCursorBlink(true)
                                searchText = ""
                                searchY = 0
                                clearScreen()
                                drawButtons(mainButtons)
                                drawOrderList()
                                drawSearch(0)
                            end
                        end
                    end
                end
            end

            for _, v in pairs(mainButtons) do
                if event[3] >= v[2] and event[3] < (v[2] + string.len(v[1]) + 2) and event[4] >= v[3] and event[4] < (v[3] + 3) then
                    if v[1] == "Clear" and #order > 0 then
                        if mode == 1 or mode == 2 then
                            order = {}
                            orderY = 1
                            editing = {}
                            searchText = ""
                            searchY = 0
                            mode = 1
                            term.setCursorBlink(true)
                            clearScreen()
                            drawButtons(mainButtons)
                            drawOrderList()
                            drawSearch(0)
                        end
                    elseif v[1] == "Pay" and #order > 0 and total > 0 then
                        if mode ==1 or mode == 2 then
                            local pay = false

                            if mode == 2 then --In config
                                if not editing[1] then --Editing item in order
                                    if editing[2][4] then
                                        if editing[2][5] ~= "" then --prevent nil error with tonumber
                                            if tonumber(editing[2][5]) <= editing[2][7] and tonumber(editing[2][5]) >= editing[2][6] then --In range set by min and max (Inclusive)
                                                pay = true --Quantity not nil and in range
                                            end
                                        end
                                    else
                                        pay = true --Quantity not editing so always valid
                                    end
                                else
                                    pay = true --Editing item not in order
                                end
                            else
                                pay = true --Not in config
                            end

                            if pay then
                                lastMode = mode
                                mode = 3
                                drawPayment(true, true)
                                term.setCursorBlink(false)
                                id = 0
                                pin = ""
                                isPin = false
                            end
                        end
                    end
                end
            end
        end
    elseif event[1] == "disk" then
        if mode == 3 then
            if not isPin then
                local tempId = disk.getID(drive)
                if tempId ~= nil then
                    id = tempId
                    isPin = true
                    drawPin(id)
                else
                    drawPayment(false, false)
                    term.setBackgroundColor(backgroundColor)
                    term.setTextColor(colors.white)
                    writeCenter("Disk id invalid", 13)
                    sleep(3)
                    drawPayment(true, true)
                end
            end
        end
    end
end
