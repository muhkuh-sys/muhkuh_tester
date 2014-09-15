<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text" omit-xml-declaration="yes" indent="no"/>

<xsl:template match="/MuhkuhTest">
<xsl:text>require("muhkuh_cli_init")
require("test_system")

-- This is a list of all available test cases in this test suite.
-- The test cases are specified by a number starting at 1.
local auiTestCases = {
</xsl:text>
<xsl:for-each select="Testcase"><xsl:value-of select="concat('&#9;', position(), substring(',', position()!=last(), 1), '&#xa;')" /></xsl:for-each>
<xsl:text>}

local fTestResult = test_system.run(arg, auiTestCases)
if fTestResult==true then
        print("OK!")
elseif fTestResult==false then
        error("The test suite failed!")
end
</xsl:text>
</xsl:template>

</xsl:stylesheet>
