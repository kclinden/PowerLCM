function Connect-vLCMServer {
<#
    .SYNOPSIS
    Connect to a vLCM Server

    .DESCRIPTION
    Connect to a vLCM Server and generate a connection object with Servername, Token etc

    .PARAMETER Server
    vLCM Server to connect to

    .PARAMETER Username
    Username to connect with

    .PARAMETER Password
    Password to connect with

    .PARAMETER Credential
    Credential object to connect with

    .PARAMETER IgnoreCertRequirements
    Ignore requirements to use fully signed certificates

    .PARAMETER SslProtocol
    Alternative Ssl protocol to use from the default
    Windows PowerShell: Ssl3, Tls, Tls11, Tls12
    PowerShell Core: Tls, Tls11, Tls12

    .INPUTS
    System.String
    System.SecureString
    Management.Automation.PSCredential
    Switch

    .OUTPUTS
    System.Management.Automation.PSObject.

    .EXAMPLE
    Connect-vLCMServer -Server vlcmappliance01.domain.local -Credential (Get-Credential)

    .EXAMPLE
    $SecurePassword = ConvertTo-SecureString “P@ssword” -AsPlainText -Force
    Connect-vLCMServer -Server vlcmappliance01.domain.local -Username admin@localhost -Password $SecurePassword -IgnoreCertRequirements
#>
[CmdletBinding(DefaultParametersetName="Username")][OutputType('System.Management.Automation.PSObject')]

    Param (

        [parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Server,

        [parameter(Mandatory=$true,ParameterSetName="Username")]
        [ValidateNotNullOrEmpty()]
        [String]$Username,

        [parameter(Mandatory=$true,ParameterSetName="Password")]
        [ValidateNotNullOrEmpty()]
        [SecureString]$Password,

        [Parameter(Mandatory=$true,ParameterSetName="Credential")]
        [ValidateNotNullOrEmpty()]
        [Management.Automation.PSCredential]$Credential,

        [parameter(Mandatory=$false)]
        [Switch]$IgnoreCertRequirements,

        [parameter(Mandatory=$false)]
        [ValidateSet('Ssl3', 'Tls', 'Tls11', 'Tls12')]
        [String]$SslProtocol
    )

    # --- Handle untrusted certificates if necessary
    $SignedCertificates = $true

    if ($PSBoundParameters.ContainsKey("IgnoreCertRequirements") ){

        if (!$IsCoreCLR) {

            if ( -not ("TrustAllCertsPolicy" -as [type])) {

                Add-Type @"
                using System.Net;
                using System.Security.Cryptography.X509Certificates;
                public class TrustAllCertsPolicy : ICertificatePolicy {
                    public bool CheckValidationResult(
                        ServicePoint srvPoint, X509Certificate certificate,
                        WebRequest request, int certificateProblem) {
                        return true;
                    }
                }
"@
            }
            [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

        }

        $SignedCertificates = $false

    }

    # --- Security Protocol
    $SslProtocolResult = 'Default'

    if ($PSBoundParameters.ContainsKey("SslProtocol") ){

        if (!$IsCoreCLR) {

            $CurrentProtocols = ([System.Net.ServicePointManager]::SecurityProtocol).toString() -split ', '
            if (!($SslProtocol -in $CurrentProtocols)){

                [System.Net.ServicePointManager]::SecurityProtocol += [System.Net.SecurityProtocolType]::$($SslProtocol)
            }
        }
        $SslProtocolResult = $SslProtocol
    }

    # --- Convert Secure Credentials to a format for sending in the JSON payload
    if ($PSBoundParameters.ContainsKey("Credential")){

        $Username = $Credential.UserName
        $JSONPassword = $Credential.GetNetworkCredential().Password
    }

    if ($PSBoundParameters.ContainsKey("Password")){

        $JSONPassword = (New-Object System.Management.Automation.PSCredential("username", $Password)).GetNetworkCredential().Password
    }

    try {

        # --- Create Invoke-RestMethod Parameters
        $JSON = @{
            username = $Username
            password = $JSONPassword
        } | ConvertTo-Json

        $Params = @{

            Method = "POST"
            URI = "https://$($Server)/lcm/api/v1/login"
            Headers = @{
                "Accept"="application/json";
                "Content-Type" = "application/json";
            }
            Body = $JSON

        }

        if ((!$SignedCertificate) -and ($IsCoreCLR)) {

            $Params.Add("SkipCertificateCheck", $true)

        }

        if (($SslProtocolResult -ne 'Default') -and ($IsCoreCLR)) {

            $Params.Add("SslProtocol", $SslProtocol)

        }

        $Response = Invoke-RestMethod @Params

        # --- Create Output Object
        $Global:vLCMConnection = [PSCustomObject] @{

            Server = "https://$($Server)"
            Token = $Response.token
            Username = $Username
            SignedCertificates = $SignedCertificates
            SslProtocol = $SslProtocolResult
        }

    }
    catch [Exception]{

        throw

    }

    Write-Output $vLCMConnection

}
