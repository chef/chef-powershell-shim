@ECHO OFF

IF DEFINED VAULT_UTIL_ACCOUNTS (
  vault-util.exe configure-accounts
)

IF DEFINED VAULT_UTIL_SECRETS (
  FOR /F "USEBACKQ TOKENS=*" %%F IN (`vault-util.exe fetch-secret-env --format batch`) DO SET %%F
)