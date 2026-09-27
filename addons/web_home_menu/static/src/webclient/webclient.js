import { onWillDestroy } from "@odoo/owl";
import { useBus, useService } from "@web/core/utils/hooks";
import { WebClient } from "@web/webclient/webclient";
import { HomeMenuNavBar } from "../navbar/navbar";

export class WebClientHomeMenu extends WebClient {
    static components = { ...WebClient.components, NavBar: HomeMenuNavBar };

    setup() {
        super.setup();
        this.homeMenu = useService("home_menu");
        useBus(this.env.bus, "HOME-MENU:TOGGLED", () => {
            document.body.classList.toggle("o_home_menu_background", this.homeMenu.hasHomeMenu());
        });
        onWillDestroy(() => document.body.classList.remove("o_home_menu_background"));
    }

    /**
     * Displays the home menu instead of the first app when there is no action
     * to load (fresh login, "/odoo" url, ...).
     *
     * @override
     */
    _loadDefaultApp() {
        return this.homeMenu.toggle(true);
    }
}
