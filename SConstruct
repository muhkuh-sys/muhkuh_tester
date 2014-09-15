# -*- coding: utf-8 -*-
#-------------------------------------------------------------------------#
#   Copyright (C) 2014 by Christoph Thelen                                #
#   doc_bacardi@users.sourceforge.net                                     #
#                                                                         #
#   This program is free software; you can redistribute it and/or modify  #
#   it under the terms of the GNU General Public License as published by  #
#   the Free Software Foundation; either version 2 of the License, or     #
#   (at your option) any later version.                                   #
#                                                                         #
#   This program is distributed in the hope that it will be useful,       #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of        #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         #
#   GNU General Public License for more details.                          #
#                                                                         #
#   You should have received a copy of the GNU General Public License     #
#   along with this program; if not, write to the                         #
#   Free Software Foundation, Inc.,                                       #
#   59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.             #
#-------------------------------------------------------------------------#


#----------------------------------------------------------------------------
#
# Set up the Muhkuh Build System.
#

SConscript('mbs/SConscript')
Import('env_default')

import os.path


#----------------------------------------------------------------------------
#
# Build the documentation.
#

# Get the default attributes.
aAttribs = env_default['ASCIIDOC_ATTRIBUTES']
# Add some custom attributes.
aAttribs.update(dict({
	# Use ASCIIMath formulas.
	'asciimath': True,

	# Embed images into the HTML file as data URIs.
	'data-uri': True,

	# Use icons instead of text for markers and callouts.
	'icons': True,

	# Use numbers in the table of contents.
	'numbered': True,
	
	# Generate a scrollable table of contents on the left of the text.
	'toc2': True,

	# Use 4 levels in the table of contents.
	'toclevels': 4
}))

doc = env_default.Asciidoc('targets/doc/org.muhkuh.tools.muhkuh_tester.html', 'README.asciidoc', ASCIIDOC_BACKEND='html5', ASCIIDOC_ATTRIBUTES=aAttribs)


#----------------------------------------------------------------------------
#
# Build the artifacts.
#

tArcList0 = env_default.ArchiveList('zip')

tArcList0.AddFiles('',
	'ivy/org.muhkuh.tools.muhkuh_tester_cli/install.xml')

tArcList0.AddFiles('doc/',
	doc)

tArcList0.AddFiles('lua/',
	'lua/parameters.lua',
	'lua/test_system.lua')

tArcList0.AddFiles('templates/',
	'templates/parameters.xsl',
	'templates/system.xsl')


strArtifactPath = 'targets/ivy/repository/org/muhkuh/tools/muhkuh_tester_cli/%s' % env_default.ArtifactVersion_Get()
tArc0 = env_default.Archive(os.path.join(strArtifactPath, 'muhkuh_tester_cli-%s.zip' % env_default.ArtifactVersion_Get()), None, ARCHIVE_CONTENTS=tArcList0)


env_default.ArtifactVersion(os.path.join(strArtifactPath, 'ivy-%s.xml' % env_default.ArtifactVersion_Get()), 'ivy/org.muhkuh.tools.muhkuh_tester_cli/ivy.xml')

