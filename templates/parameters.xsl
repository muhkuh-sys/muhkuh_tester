<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text" omit-xml-declaration="yes" indent="no"/>

<xsl:template match="/MuhkuhTest">
<xsl:for-each select="Testcase/Parameter"><xsl:value-of select="concat(position(), ':', @name, '=', ., '&#xa;')" /></xsl:for-each>
</xsl:template>

</xsl:stylesheet>
