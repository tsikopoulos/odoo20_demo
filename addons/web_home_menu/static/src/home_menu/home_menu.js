import { Component, signal, t, useListener, usePlugin, useProps } from "@odoo/owl";
import { useHotkey } from "@web/core/hotkeys/hotkey_hook";
import { OfflinePlugin } from "@web/core/offline/offline_plugin";
import { useService } from "@web/core/utils/hooks";

const EDITABLE_TAGS = ["INPUT", "TEXTAREA", "SELECT"];

export class HomeMenu extends Component {
    static template = "web_home_menu.HomeMenu";
    props = useProps({
        apps: t.array(t.object()),
        className: t.string().optional(),
    });
    root = signal.ref();

    setup() {
        this.menuService = useService("menu");
        this.command = useService("command");
        this.homeMenu = useService("home_menu");
        this.ui = useService("ui");
        this.offlinePlugin = usePlugin(OfflinePlugin);

        const repeatable = { allowRepeat: true };
        useHotkey("ArrowRight", () => this.moveFocus(1), repeatable);
        useHotkey("ArrowLeft", () => this.moveFocus(-1), repeatable);
        useHotkey("ArrowDown", () => this.moveFocus(this.columnCount()), repeatable);
        useHotkey("ArrowUp", () => this.moveFocus(-this.columnCount()), repeatable);
        useHotkey("escape", () => this.homeMenu.toggle(false));
        useListener(window, "keydown", this.onWindowKeydown.bind(this));
    }

    appElements() {
        return [...(this.root()?.querySelectorAll(".o_app") || [])];
    }

    /**
     * @returns {number} the number of apps displayed on the first row
     */
    columnCount() {
        const apps = this.appElements();
        if (!apps.length) {
            return 1;
        }
        const firstRowTop = apps[0].offsetTop;
        return apps.filter((el) => el.offsetTop === firstRowTop).length;
    }

    /**
     * Moves the focus by the given number of apps, wrapping around.
     *
     * @param {number} delta
     */
    moveFocus(delta) {
        const apps = this.appElements();
        if (!apps.length) {
            return;
        }
        const current = apps.indexOf(document.activeElement);
        const next = current === -1 ? 0 : (((current + delta) % apps.length) + apps.length) % apps.length;
        apps[next].focus();
    }

    isAvailable(app) {
        return !this.offlinePlugin.isOffline() || this.offlinePlugin.isAvailableOffline(app.actionID);
    }

    openApp(app) {
        return this.menuService.selectMenu(app);
    }

    /**
     * Typing while the home menu is displayed opens the command palette in the
     * "menus" namespace, with the typed character as first search term.
     *
     * @param {KeyboardEvent} ev
     */
    onWindowKeydown(ev) {
        if (ev.defaultPrevented || ev.isComposing || ev.ctrlKey || ev.metaKey || ev.altKey) {
            return;
        }
        if (ev.key.length !== 1 || ev.key === " ") {
            return; // not a printable character
        }
        if (this.ui.activeElement !== document) {
            return; // a dialog (e.g. the command palette itself) is open
        }
        const target = ev.target;
        if (
            target instanceof HTMLElement &&
            (target.isContentEditable || EDITABLE_TAGS.includes(target.tagName))
        ) {
            return;
        }
        ev.preventDefault();
        this.command.openMainPalette({ searchValue: `/${ev.key}` });
    }
}
