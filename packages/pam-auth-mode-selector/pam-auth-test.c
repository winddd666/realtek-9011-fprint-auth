#include <security/pam_appl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int
conversation (int                        num_msg,
              const struct pam_message **msg,
              struct pam_response      **resp,
              void                      *data)
{
  struct pam_response *responses;

  (void) data;

  responses = calloc ((size_t) num_msg, sizeof (*responses));
  if (!responses)
    return PAM_BUF_ERR;

  for (int i = 0; i < num_msg; i++)
    {
      switch (msg[i]->msg_style)
        {
        case PAM_PROMPT_ECHO_ON:
          responses[i].resp = strdup ("");
          break;

        case PAM_PROMPT_ECHO_OFF:
          {
            char *password = getpass (msg[i]->msg ? msg[i]->msg : "Password: ");
            responses[i].resp = password ? strdup (password) : NULL;
          }
          break;

        case PAM_ERROR_MSG:
        case PAM_TEXT_INFO:
          if (msg[i]->msg)
            fprintf (stderr, "%s\n", msg[i]->msg);
          break;

        default:
          free (responses);
          return PAM_CONV_ERR;
        }
    }

  *resp = responses;
  return PAM_SUCCESS;
}

int
main (int argc, char **argv)
{
  struct pam_conv conv = { conversation, NULL };
  pam_handle_t *handle = NULL;
  int auth_only;
  int status;

  if (argc != 3 && argc != 4)
    {
      fprintf (stderr, "Usage: %s PAM_SERVICE USER [--auth-only]\n", argv[0]);
      return EXIT_FAILURE;
    }

  auth_only = argc == 4 && strcmp (argv[3], "--auth-only") == 0;
  if (argc == 4 && !auth_only)
    {
      fprintf (stderr, "Unknown option: %s\n", argv[3]);
      return EXIT_FAILURE;
    }

  status = pam_start (argv[1], argv[2], &conv, &handle);
  if (status == PAM_SUCCESS)
    status = pam_authenticate (handle, 0);
  if (status == PAM_SUCCESS && !auth_only)
    status = pam_acct_mgmt (handle, 0);

  fprintf (stderr, "PAM result: %s\n", pam_strerror (handle, status));
  if (handle)
    pam_end (handle, status);

  return status == PAM_SUCCESS ? EXIT_SUCCESS : EXIT_FAILURE;
}
