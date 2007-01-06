/*
 *  PreferenceControllerStrings.h
 *  iScrobbler
 *
 *  Created by Sam Ley on Feb 14, 2003.
 *  Released under the GPL, license details available at
 *  http://iscrobbler.sourceforge.net
 *
 *  This file contains useful strings that get included into the preferencecontroller. Their
 *  purpose here is to prevent me from being forced into writing extraordinarily unreadable
 *  code.
 */

#define NO_CONNECTION_SHORT NSLocalizedString(@"No connection yet.", "Short error message when no connection is made")

#define NO_CONNECTION_LONG NSLocalizedString(@"No connection yet, waiting for data.", "Long error message when no connection is made")

#define SUBMISSION_SUCCESS_SHORT NSLocalizedString(@"Last Submission Successful", "Short error message when submission is successful")

#define SUBMISSION_SUCCESS_LONG NSLocalizedString(@"Last Submission Successful - The connection was properly established and the server reports a transfer success.", "Long error message when submission is successful")

#define SUBMISSION_SUCCESS_OUTOFDATE_SHORT NSLocalizedString(@"Success - New Version Available!", "Short error message when submission is successful and there is a new version available")

#define SUBMISSION_SUCCESS_OUTOFDATE_LONG NSLocalizedString(@"Last Submission Successful - The connection was properly established and the server reports a transfer success. Additionally, there is a new version of iScrobbler available! Download today for access to important fixes and enhancements.", "Long error message when submission is successful and there is a new version available.")

#define FAILURE_SHORT NSLocalizedString(@"Failure - Server Error", "Short error message when submission fails due to server error.")

#define FAILURE_LONG NSLocalizedString(@"Server Error - A connection was established to the server, but the server failed to collect the data. This is probably a temporary problem. If it persists more than a few hours, please submit a bug report.", "Long error message when submission fails due to server error.")

#define AUTH_SHORT NSLocalizedString(@"Authentication Failed", "Short error message when submission fails due to authentication failure.")

#define AUTH_LONG NSLocalizedString(@"Authentication Failed - Your username or password was not accepted by the server, please reenter them and try again. If you do not have an account, please visit http://www.audioscrobbler.com to register.", "Long error message when submission fails due to authentication failure.")

#define COULDNT_RESOLVE_SHORT NSLocalizedString(@"Couldn't Resolve Host", "Short error message when host cannot be resolved")

#define COULDNT_RESOLVE_LONG NSLocalizedString(@"Sorry, the host could not be resolved. Your internet connection may be down. If you can visit http://www.audioscrobbler.com in your web browser, then there may be a bug in the software, please submit a bug report!", "Long error message when host cannot be resolved")

#define NOT_FOUND_SHORT NSLocalizedString(@"404 Error, file not found!", "Short error message when the server reports a 404 error")

#define NOT_FOUND_LONG NSLocalizedString(@"The script on the server was not located! Please submit a bug report!", "Long error message when the server reports a 404 error")

#define UNKNOWN_SHORT NSLocalizedString(@"Unknown Response From Server", "Short error message when server reports an unknown error")

#define UNKNOWN_LONG NSLocalizedString(@"The server response is unknown.. Please submit a bug report with a description of the circumstance, and a copy of the response data.", "Long error message when server reports an unknown error")

#define PASS_STORED NSLocalizedString(@"Password Stored", "Message given when password is stored successfully")

#define PASS_NOT_STORED NSLocalizedString(@"No Password Stored", "Message given when password is NOT stored.")

#define NOT_UPTODATE NSLocalizedString(@"A new version of iScrobbler is available! Download it today!", "Message given when a new version is found")

#define SPAM_PROTECT_LONG NSLocalizedString(@"A connection was established, but spam prevention blocked the submission. You must wait one minute between submissions. Also, submissions that are a duplicate of the previous submission are not accepted by the server.", "Message given when spam protection activates.")

#define SPAM_PROTECT_SHORT NSLocalizedString(@"Waiting...", "Short message given when spam protection activates.")
