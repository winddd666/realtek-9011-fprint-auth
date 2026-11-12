#define PAM_SM_AUTH

#include <security/pam_appl.h>
#include <security/pam_ext.h>
#include <security/pam_modules.h>

#include <stdlib.h>
#include <string.h>

#define FINGERPRINT_MARKER ":fp"
#define MODE_ENV "FPRINT_AUTH_MODE"

static int
select_fingerprint (const char *configured_mode,
                    const char *token)
{
  if (token && strcmp (token, FINGERPRINT_MARKER) == 0)
    return 1;

  return configured_mode && strcmp (configured_mode, "fingerprint") == 0 &&
         (!token || token[0] == '\0');
}

PAM_EXTERN int
pam_sm_authenticate (pam_handle_t *pamh,
                     int           flags,
                     int           argc,
                     const char  **argv)
{
  const char *configured_mode = getenv (MODE_ENV);
  const char *token = NULL;
  int status;

  (void) flags;
  (void) argc;
  (void) argv;

  status = pam_get_authtok (pamh, PAM_AUTHTOK, &token,
                            "Password, or type :fp for fingerprint: ");
  if (status != PAM_SUCCESS)
    return PAM_IGNORE;

  if (!select_fingerprint (configured_mode, token))
    {
      pam_putenv (pamh, "FPRINT_AUTH_SELECTED=password");
      return PAM_IGNORE;
    }

  pam_set_item (pamh, PAM_AUTHTOK, NULL);
  pam_putenv (pamh, "FPRINT_AUTH_SELECTED=fingerprint");
  return PAM_SUCCESS;
}

PAM_EXTERN int
pam_sm_setcred (pam_handle_t *pamh,
                int           flags,
                int           argc,
                const char  **argv)
{
  (void) pamh;
  (void) flags;
  (void) argc;
  (void) argv;

  return PAM_SUCCESS;
}

#ifdef PAM_MODULE_ENTRY
PAM_MODULE_ENTRY ("pam_auth_mode_selector");
#endif
