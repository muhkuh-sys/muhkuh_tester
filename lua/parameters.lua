module("parameters", package.seeall)



function test_uint32(tValue)
	local fResult = false
	local strError = ""
	
	-- Try to convert the value to a number.
	local ulValue = tonumber(tValue)
	if ulValue==nil then
		strError = "The argument is no number!"
	elseif ulValue<0 or ulValue>0xffffffff then
		strError = "The number exceeds the range of a 32bit value."
	else
		fResult = true
	end
	
	return fResult, strError
end



function split_string(strElements)
	local astrResult = {}
	
	for strElement in string.gmatch(strElements, "([^,]+),?") do
		table.insert(astrResult, strElement)
	end
	
	return astrResult
end



function test_choice_single(tValue, astrElements)
	local fResult = false
	local strError = ""
	
	local strValue = tostring(tValue)
	
	-- Split the allowed values by comma.
	local astrElements = split_string(astrElements)
	
	-- Find the selected value in the list.
	for iCnt,strElement in ipairs(astrElements) do
		if strElement==strValue then
			fResult = true
			break
		end
	end
	
	if fResult==false then
		strError = string.format("Unknown value: %s . Possible values are: %s", strValue, table.concat(astrElements, ", "))
	end
	
	return fResult, strError
end



function test_choice_multiple(tValue, astrElements)
	local fResult = true
	local strError = ""
	
	-- Get the list of selected values.
	local astrValue = split_string(tostring(tValue))
	
	-- Split the allowed values by comma.
	local astrElements = split_string(astrElements)
	
	-- Loop over all selected values.
	for iCnt0, strValue in ipairs(astrValue) do
		local fFoundValue = false
		
		-- Find the value in the list.
		for iCnt,strElement in ipairs(astrElements) do
			if strElement==strValue then
				fFoundValue = true
				break
			end
		end
		
		if fFoundValue==false then
			strError = strError .. string.format("Unknown value: %s . ", strValue)
		end
		fResult = fResult and fFoundValue
	end
	
	if fResult==false then
		strError = strError .. string.format("Possible values are: %s", table.concat(astrElements, ", "))
	end
	
	return fResult, strError
end


