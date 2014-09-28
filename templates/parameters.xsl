<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="text" omit-xml-declaration="yes" indent="no"/>

<xsl:template match="/MuhkuhTest">
	<xsl:for-each select="Testcase">
		<xsl:variable name="testcase_position" select="position()" />
		
		<xsl:for-each select="Parameter">
			<xsl:value-of select="concat($testcase_position, ':', @name, '=', ., '&#xa;')" />
		</xsl:for-each>
	</xsl:for-each>
</xsl:template>

</xsl:stylesheet>
