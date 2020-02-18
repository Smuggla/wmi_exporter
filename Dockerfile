FROM mcr.microsoft.com/windows/servercore:ltsc2019 AS builder

# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324
SHELL ["powershell.exe", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ENV GOLANG_VERSION 1.13.8

RUN $url = ('https://golang.org/dl/go{0}.windows-amd64.zip' -f $env:GOLANG_VERSION); \
	Write-Host ('Downloading {0} ...' -f $url); \
	Invoke-WebRequest -Uri $url -OutFile 'go.zip'; \
	\
	$sha256 = 'aaf0888907144ca7070c8dad03fcf1308f77a42d2f6e4d2a609e64e9ae73cf4f'; \
	Write-Host ('Verifying sha256 ({0}) ...' -f $sha256); \
	if ((Get-FileHash go.zip -Algorithm sha256).Hash -ne $sha256) { \
		Write-Host 'FAILED!'; \
		exit 1; \
	}; \
	\
	Write-Host 'Expanding ...'; \
	Expand-Archive go.zip -DestinationPath C:\; \
	\
	Write-Host 'Removing ...'; \
	Remove-Item go.zip -Force; \
	\
	Write-Host 'Complete.';

ENV GIT_VERSION 2.25.0
ENV GIT_DOWNLOAD_URL https://github.com/git-for-windows/git/releases/download/v${GIT_VERSION}.windows.1/MinGit-${GIT_VERSION}-64-bit.zip
ENV GIT_SHA256 30bbd4ba6ca21fe97d43397a3d4e0e24be6ae2660b517cc1b96350195e48adea

RUN [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ; \
		Invoke-WebRequest -UseBasicParsing $env:GIT_DOWNLOAD_URL -OutFile git.zip; \
    if ((Get-FileHash git.zip -Algorithm sha256).Hash -ne $env:GIT_SHA256) {exit 1} ; \
    Expand-Archive git.zip -DestinationPath C:\git; \
    Remove-Item git.zip

FROM mcr.microsoft.com/windows/servercore/insider:10.0.17763.107 as compiler
# Insider is needed to address "panic: Failed to load netapi32.dll: The specified module could not be found" https://github.com/golang/go/issues/21867
COPY --from=builder /go /go
COPY --from=builder /git /git

ENV GOPATH C:\\gopath
WORKDIR $GOPATH

#USER ContainerAdministrator
RUN setx /m PATH "%PATH%;C:\%GOPATH%\bin;C:\go\bin;C:\git\cmd;C:\git\mingw64\bin;C:\git\usr\bin"
#USER ContainerUser

ENV GOOS windows
ENV GOARCH amd64
RUN go get -u github.com/prometheus/promu
RUN go get -u github.com/martinlindhe/wmi_exporter

FROM mcr.microsoft.com/windows/servercore:ltsc2019 AS base

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ENV COLLECTORS="cpu,cs,container,logical_disk,net,os,service,system"  \
    LISTEN_ADDR=0.0.0.0 \
    METRIC_PORT=9182 \ 
    METRIC_PATH="/metrics"
RUN echo $ENV:COLLECTORS

COPY --from=compiler /gopath/bin/wmi_exporter.exe /wmi_exporter/wmi_exporter.exe
COPY wmi_exporter.ps1 .
ENTRYPOINT powershell ./wmi_exporter.ps1

EXPOSE 9182 
