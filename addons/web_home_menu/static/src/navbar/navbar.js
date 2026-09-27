import { _t } from "@web/core/l10n/translation";
import { useService } from "@web/core/utils/hooks";
import { NavBar } from "@web/webclient/navbar/navbar";

/**
 * Navbar whose top-left entry toggles the home menu instead of opening the
 * apps dropdown. On small screens the app sidebar is kept, but its "All Apps"
 * button opens the home menu.
 */
export class HomeMenuNavBar extends NavBar {
    static template = "web_home_menu.NavBar";

    setup() {
        super.setup();
        this.homeMenu = useService("home_menu");
    }

    isHomeMenuBack() {
        return this.homeMenu.hasHomeMenu() && this.homeMenu.hasBackgroundAction();
    }

    homeMenuToggleTitle() {
        return this.isHomeMenuBack() ? _t("Back") : _t("Home Menu");
    }

    onHomeMenuToggle() {
        return this.homeMenu.toggle();
    }

    /**
     * @override
     */
    onAllAppsBtnClick() {
        this._closeAppMenuSidebar();
        return this.homeMenu.toggle(true);
    }
}
