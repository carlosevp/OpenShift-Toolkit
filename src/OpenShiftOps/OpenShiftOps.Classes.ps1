# OpenShiftOps exception types. Fail closed for safety-critical conditions.

class OcpException : System.Exception {
    OcpException([string]$Message) : base($Message) { }
    OcpException([string]$Message, [System.Exception]$Inner) : base($Message, $Inner) { }
}

class OcpAuthenticationException : OcpException {
    OcpAuthenticationException([string]$Message) : base($Message) { }
}

class OcpClusterIdentityException : OcpException {
    OcpClusterIdentityException([string]$Message) : base($Message) { }
}

class OcpProtectedProjectException : OcpException {
    OcpProtectedProjectException([string]$Message) : base($Message) { }
}

class OcpSafetyException : OcpException {
    OcpSafetyException([string]$Message) : base($Message) { }
}

class OcpPermissionException : OcpException {
    OcpPermissionException([string]$Message) : base($Message) { }
}

class OcpTimeoutException : OcpException {
    OcpTimeoutException([string]$Message) : base($Message) { }
}

class OcpCliException : OcpException {
    [int]$ExitCode
    [string]$StandardError
    [string[]]$Arguments

    OcpCliException([string]$Message, [int]$ExitCode, [string]$StandardError, [string[]]$Arguments) : base($Message) {
        $this.ExitCode = $ExitCode
        $this.StandardError = $StandardError
        $this.Arguments = $Arguments
    }
}

class OcpConfigurationException : OcpException {
    OcpConfigurationException([string]$Message) : base($Message) { }
}

class OcpValidationException : OcpException {
    OcpValidationException([string]$Message) : base($Message) { }
}

class OcpStalePlanException : OcpException {
    OcpStalePlanException([string]$Message) : base($Message) { }
}

class OcpBackupException : OcpException {
    OcpBackupException([string]$Message) : base($Message) { }
}
