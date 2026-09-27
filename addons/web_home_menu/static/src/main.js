import { startWebClient } from "@web/start";
import { WebClientHomeMenu } from "./webclient/webclient";

/**
 * Replaces web/static/src/main.js (see the manifest) so that the web client
 * started is the one displaying the home menu.
 */
startWebClient(WebClientHomeMenu);
