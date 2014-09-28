<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="xml" indent="yes"/>

<xsl:template match="/MuhkuhTest">
	<xsl:element name="project">
		<xsl:attribute name="name">try01_test</xsl:attribute>
		<xsl:attribute name="default">all</xsl:attribute>
		
		<xsl:element name="target">
			<xsl:attribute name="name">all</xsl:attribute>
			
			<xsl:for-each select="Testcase">
				<xsl:element name="ant">
					<xsl:attribute name="dir"><xsl:value-of select="concat('${ivy.settings.dir}/${path.', @id, '}')"/></xsl:attribute>
					<xsl:attribute name="antfile">install.xml</xsl:attribute>
					<xsl:attribute name="target">install_testcase</xsl:attribute>
					<xsl:attribute name="inheritAll">true</xsl:attribute>
					<xsl:attribute name="inheritRefs">true</xsl:attribute>
					
					<xsl:element name="property">
						<xsl:attribute name="name">muhkuh.testcase.module_name</xsl:attribute>
						<xsl:value-of select="concat('test', format-number(position(), '00'))" />
					</xsl:element>
					
					<xsl:element name="property">
						<xsl:attribute name="name">muhkuh.testcase.test_name</xsl:attribute>
						<xsl:value-of select="@name" />
					</xsl:element>
				</xsl:element>
			</xsl:for-each>
		</xsl:element>
	</xsl:element>
</xsl:template>

</xsl:stylesheet>
