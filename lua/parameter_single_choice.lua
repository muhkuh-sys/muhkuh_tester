-- Create the parameter class.
local class = require 'pl.class'
local Parameter = require 'parameter'
local Parameter_SingleChoice = class(Parameter)


function Parameter_SingleChoice:_init(strOwner, strName, strHelp, tLogWriter, strLogLevel)
  self:super(strOwner, strName, strHelp, tLogWriter, strLogLevel)

  -- The "penlight" module is used to parse the constraints.
  self.pl = require'pl.import_into'()

  self.atConstraint = nil
end


function Parameter_SingleChoice:constraint(tConstraint)
  local atChoices
  if type(tConstraint)=='table' then
    -- Check if all indices are non-0 numbers and the values in the table are strings.
    for tKey, tValue in pairs(tConstraint) do
      if type(tKey)~='number' then
        self.tLog.error('The constraint table contains a non-numeric key.')
        error('invalid constraint')
      end
      local lNum, fNum = math.modf(tKey)
      if fNum~=0 then
        self.tLog.error('The constraint table contains a non-integer number as a key.')
        error('invalid constraint')
      end
      if lNum==0 then
        self.tLog.error('The constraint table contains a 0 as a key.')
        error('invalid constraint')
      end
    end

    atChoices = {}
    for _, tChoice in ipairs(tConstraint) do
      strChoice = self.pl.stringx.strip(tostring(tChoice))
      if strChoice~='' then
        if self.pl.tablex.find(atChoices, strChoice)~=nil then
          self.tLog.error('The constraints contains more than one entry of "%s".', strChoice)
          error('invalid constraint')
        end
        table.insert(atChoices, strChoice)
      end
    end

    if table.maxn(atChoices)==0 then
      self.tLog.error('The constraint table contains no values.')
      error('invalid constraint')
    end
  elseif type(tConstraint)=='string' then
    -- Split the string by comma.
    local astrElements = self.pl.stringx.split(tConstraint, ',')

    atChoices = {}
    for _, strChoice in ipairs(astrElements) do
      strChoice = self.pl.stringx.strip(strChoice)
      if strChoice~='' then
        table.insert(atChoices, strChoice)
      end
    end

    if table.maxn(atChoices)==0 then
      self.tLog.error('The constraint string contains no values.')
      error('invalid constraint')
    end
  else
    self.tLog.error('The constraint must be a table or a string. Here it is of type "%s".', type(tConstraint))
    error('invalid constraint')
  end


  self.atConstraint = atChoices

  return self
end


function Parameter_SingleChoice:__validate(tValue)
  local fIsValid = false
  local tValidatedValue
  local strMessage
  local strValue = self.pl.stringx.strip(tostring(tValue))

  if self.atConstraint==nil then
    strMessage = 'Unable to validate the parameter as a single choice. No constraint is set.'
  elseif self.pl.tablex.find(self.atConstraint, strValue)==nil then
    strMessage = string.format('The value %s is not in the list of allowed values, which is %s.', strValue, table.concat(self.atConstraint, ', '))
  else
    fIsValid = true
    tValidatedValue = strValue
  end

  return fIsValid, tValidatedValue, strMessage
end


return Parameter_SingleChoice
