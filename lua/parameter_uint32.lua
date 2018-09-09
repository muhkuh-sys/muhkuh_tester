-- Create the parameter class.
local class = require 'pl.class'
local Parameter = require 'parameter'
local Parameter_UINT32 = class(Parameter)


function Parameter_UINT32:_init(strOwner, strName, strHelp, tLogWriter, strLogLevel)
  self:super(strOwner, strName, strHelp, tLogWriter, strLogLevel)
end


function Parameter_UINT32:__validate(tValue)
  local fIsValid = false
  local tValidatedValue
  local strMessage = nil

  local ulValue = tonumber(tValue)
  if ulValue==nil then
    strMessage = string.format('The value %s could not be converted to a number.', tostring(tValue))
  elseif ulValue<0 or ulValue>0xffffffff then
    strMessage = string.format('The value %d is not in the allowed range of [0,4294967295].', ulValue)
  else
    fIsValid = true
    tValidatedValue = ulValue
  end

  return fIsValid, tValidatedValue, strMessage
end


return Parameter_UINT32
