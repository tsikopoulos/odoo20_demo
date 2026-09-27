import { Component, computed, onMounted, onWillUnmount, signal, useProps, xml } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { Mutex } from "@web/core/utils/concurrency";
import { useService } from "@web/core/utils/hooks";
import { computeAppsAndMenuItems } from "@web/webclient/menus/menu_helpers";
import { HomeMenu } from "./home_menu";

// true while the home menu is displayed
const hasHomeMenu = signal(false);
// true when the home menu is displayed on top of another action
const hasBackgroundAction = signal(false);

/**
 * The home menu is a client action whose tag is "menu": the router maps that
 * action to the "/odoo" url and the breadcrumbs ignore it, exactly as they do
 * for the Enterprise home menu. It is pushed on top of the current action, so
 * the user can come back to what they were doing with the navbar toggle.
 */
export class HomeMenuAction extends Component {
    static template = xml`<HomeMenu apps="this.apps()" className="this.props.className"/>`;
    static components = { HomeMenu };
    static target = "current";
    props = useProps();

    setup() {
        this.menuService = useService("menu");
        this.apps = computed(
            () => computeAppsAndMenuItems(this.menuService.getMenuAsTree("root")).apps
        );
        onMounted(() => {
            hasHomeMenu.set(true);
            hasBackgroundAction.set(this.env.config.breadcrumbs.length > 0);
            this.env.bus.trigger("HOME-MENU:TOGGLED");
        });
        onWillUnmount(() => {
            hasHomeMenu.set(false);
            hasBackgroundAction.set(false);
            this.env.bus.trigger("HOME-MENU:TOGGLED");
        });
    }
}

registry.category("actions").add("menu", HomeMenuAction);

export const homeMenuService = {
    dependencies: ["action"],
    start(env, { action }) {
        hasHomeMenu.set(false);
        hasBackgroundAction.set(false);
        const mutex = new Mutex(); // serializes concurrent toggling requests

        return {
            hasHomeMenu() {
                return hasHomeMenu();
            },
            hasBackgroundAction() {
                return hasBackgroundAction();
            },
            /**
             * Shows or hides the home menu. Hiding it restores the action it
             * was displayed on top of, if any.
             *
             * @param {boolean} [show] toggles the home menu when omitted
             */
            toggle(show) {
                return mutex.exec(async () => {
                    const shouldShow = show === undefined ? !hasHomeMenu() : Boolean(show);
                    if (shouldShow === hasHomeMenu()) {
                        return;
                    }
                    if (shouldShow) {
                        await action.doAction("menu");
                    } else if (hasBackgroundAction()) {
                        await action.restore();
                    }
                });
            },
        };
    },
};

registry.category("services").add("home_menu", homeMenuService);
