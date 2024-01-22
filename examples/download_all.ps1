# JNC Download All
# Writen by J Pace (redmasq@gmail.com)

# MIT License
#
# Copyright (c) 2024 J Pace (redmasq@gmail.com)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Please note that the J-Novel Club API is subject to it's own terms and conditions
# and that author has no formal relationship with J-Novel Club. Please respect the
# API and it's creaters by not spamming it constantly since this does create a bit
# of traffic, particularly for first run or -forceAll being used.
#

$loginUrl = "https://labs.j-novel.club/app/v1/auth/login?format=json" # JSON is easier to handle in Powershell
$libUrl = "https://labs.j-novel.club/app/v1/me/library?format=json" # JSON is easier to handle in Powershell
$credJson = ConvertFrom-Json (Get-Content -Raw creds.json)

# 7 zip is only required for the repackaging/reprocessing
$sevenZipPath = "C:\Program Files\7-Zip\7z.exe" # Update this path according to your 7-Zip installation
if ($credJson.sevenZipPath -ne $null -and (Test-Path $credJson.sevenZipPath)) {
	$sevenZipPath = $credJson.sevenZipPath
}

$current = pwd
$downloadDir = Join-Path $current "Downloads"
$reprocess = $credJson.reprocess # Repackage the epub file if dealing with FBReader issues
$forceAll = ("-forceAll" -ieq $1) # Redownload everything


# Create the download directory if it doesn't exist
if (-not (Test-Path -Type Container $downloadDir)) {
    mkdir $downloadDir
}

# Package the creds in the expected format
# Technically redundant now, but I want to toss other optiosn into the creds file
# As configuration later
# Also, intending on encrypting the creds later
$loginPayload = @"
{
    "login": "$($credJson.username)",
    "password": "$($credJson.password)",
    "slim": false
}
"@

# Log into the J-Novel Club API and get a token
$response = Invoke-WebRequest $loginUrl -Body $loginPayload -ContentType "application/json" -Method Post
$json = ConvertFrom-Json $response.Content
$token = $json.id

# Convert the token to a secure string
$secureToken = ConvertTo-SecureString $token -AsPlainText -Force

# Make the GET request using the -Authentication and -Token parameters
# This is the library API Rest endpoint
$response = Invoke-WebRequest -Uri $libUrl -Method Get -Authentication Bearer -Token $secureToken

# Error handling? What's that? Is it tasty?
# For now, not actually handling errors for simplicity
$json = ConvertFrom-Json $response.Content

# And we walk through the JSON
$bookUrls = $json.books |
	? { $_.downloads.label -ieq "Premium EPUB" } | # Only purchased books
	? {	$forceAll -or $_.lastUpdated -eq $null -or $_.lastDownload -eq $null -or (([datetime]$_.lastUpdated) -gt ([datetime]$_.lastDownload)) } | # Unless we want everything, only get the undownloaded or updated
	% {
	$book = $_
	
	#Write-Host $_
	$message = "Adding " + $_.volume.title + ($_.lastDownload -ne $null ? " Previously Downloaded " + ([datetime]$_.lastDownload) : "")
	
	Write-Host $message
	
	[pscustomobject]@{ #enumerate the links and desired file names
		filename = $book.volume.slug + ".epub"
		link = $_.downloads.link
	}
}

if ($bookUrls -eq $null -or $bookUrls.length -eq 0) {
	Write-Host "No work to be done"
}

# Here we are finally selecting from our library and downloading
$bookUrls |
	? { $_.link } | # Only worry about the ones with non-empty links
	% { 
    $downloadUrl = $_.link
    $fileName = $_.filename
    $filePath = Join-Path $downloadDir $fileName
    Invoke-WebRequest -Uri $downloadUrl -Method Get -Authentication Bearer -Token $secureToken -OutFile $filePath

	# I've experienced problems with FBReader for unknown reasons
	# Repackaging the epub seems to help; although, the files downloaded
	# seem to be perfectly file otherwise. I had check the file order, the
	# compression, and the zip directory and saw no issues with the original
	# so I suspect it's an issue with the library being used for handling zips
	# and the lack of memory for the higher quality images, tabun.
	if ($reprocess) {
		# Temporary directory to extract the EPUB
		$tempDir = Join-Path $downloadDir "temp"
		mkdir $tempDir -Force

		# Extract the EPUB
		& "$sevenZipPath" x "$filePath" -o"$tempDir"

		# Repackage the EPUB with correct structure
		Remove-Item $filePath # Remove the original EPUB file
		move "$tempDir\mimetype" "$tempDir\!mimeType" # Add the file first by renaming it
		& "$sevenZipPath" a -tzip "$filePath" "$tempDir\!mimetype" -mx0 # Add mimetype without compression
		del "$tempDir\!mimeType" # Avoid the second add
		& "$sevenZipPath" a -tzip "$filePath" "$tempDir\*" -mx9 # Add the rest with maximum compression
		& "$sevenZipPath" rn "$filePath" !mimetype mimetype # Rename the file back; 7zip seems to add the files according to alphabetical order, but renames in place

		# Clean up the temporary directory
		Remove-Item $tempDir -Recurse -Force
	}
}