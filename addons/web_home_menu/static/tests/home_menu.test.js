import { beforeEach, expect, test } from "@odoo/hoot";
import { press, queryAll, queryAllTexts, waitFor, waitForNone } from "@odoo/hoot-dom";
import { advanceTime, animationFrame } from "@odoo/hoot-mock";
import { Component, useProps, xml } from "@odoo/owl";
import {
    contains,
    defineMenus,
    getService,
    mountWithCleanup,
} from "@web/../tests/web_test_helpers";
import { registry } from "@web/core/registry";
import { WebClientHomeMenu } from "@web_home_menu/webclient/webclient";

class TestClientAction extends Component {
    static template = xml`<div class="test_client_action">Client action</div>`;
    props = useProps();
}

beforeEach(() => {
    registry.category("actions").add("web_home_menu_test_action", TestClientAction);
    defineMenus([
        { id: 1, name: "Contacts", actionID: "web_home_menu_test_action", xmlid: "test.contacts" },
        { id: 2, name: "Sales", actionID: "web_home_menu_test_action", xmlid: "test.sales" },
    ]);
    return () => registry.category("actions").remove("web_home_menu_test_action");
});

async function mountWebClient() {
    await mountWithCleanup(WebClientHomeMenu);
    await waitFor(".o_home_menu .o_app");
}

async function openApp(xmlid, root) {
    await contains(`.o_home_menu .o_app[data-menu-xmlid='${xmlid}']`, { root }).click();
    await waitFor(".test_client_action");
    await animationFrame();
}

test.tags("desktop");
test("home menu is displayed when there is no action to load", async () => {
    await mountWebClient();
    expect(".o_home_menu").toHaveCount(1);
    expect(queryAllTexts(".o_home_menu .o_app .o_caption")).toEqual(["Contacts", "Sales"]);
    expect(".o_home_menu .o_app[data-menu-xmlid='test.sales']").toHaveAttribute(
        "href",
        "/odoo/action-web_home_menu_test_action"
    );
    expect(document.body).toHaveClass("o_home_menu_background");
    expect(".o_main_navbar .o_home_menu_toggle").toHaveCount(1);
    expect(".o_main_navbar .o_home_menu_toggle").not.toHaveClass("o_home_menu_toggle_back");
    expect(".o_main_navbar .o_menu_brand").toHaveCount(0);
    expect(getService("home_menu").hasHomeMenu()).toBe(true);
    expect(getService("home_menu").hasBackgroundAction()).toBe(false);
});

test.tags("desktop");
test("apps open from the home menu, the toggle goes back and forth", async () => {
    await mountWebClient();
    await openApp("test.sales");
    expect(".o_home_menu").toHaveCount(0);
    expect(document.body).not.toHaveClass("o_home_menu_background");
    expect(".o_main_navbar .o_menu_brand").toHaveText("Sales");
    expect(".o_main_navbar .o_home_menu_toggle").toHaveClass("o_home_menu_toggle_app");

    await contains(".o_main_navbar .o_home_menu_toggle").click();
    await waitFor(".o_home_menu");
    await animationFrame();
    expect(".test_client_action").toHaveCount(0);
    expect(".o_main_navbar .o_menu_brand").toHaveCount(0);
    expect(".o_main_navbar .o_home_menu_toggle").toHaveClass("o_home_menu_toggle_back");
    expect(getService("home_menu").hasBackgroundAction()).toBe(true);

    await contains(".o_main_navbar .o_home_menu_toggle").click();
    await waitFor(".test_client_action");
    await animationFrame();
    expect(".o_home_menu").toHaveCount(0);
    expect(".o_main_navbar .o_menu_brand").toHaveText("Sales");
});

test.tags("desktop");
test("escape returns to the action behind the home menu", async () => {
    await mountWebClient();
    await openApp("test.contacts");
    await getService("home_menu").toggle(true);
    await waitFor(".o_home_menu");

    await press("Escape");
    await waitForNone(".o_home_menu");
    expect(".test_client_action").toHaveCount(1);
});

test.tags("desktop");
test("arrow keys move the focus between the apps", async () => {
    await mountWebClient();
    await press("ArrowRight");
    expect(".o_app[data-menu-xmlid='test.contacts']").toBeFocused();
    await press("ArrowRight");
    expect(".o_app[data-menu-xmlid='test.sales']").toBeFocused();
    await press("ArrowRight");
    expect(".o_app[data-menu-xmlid='test.contacts']").toBeFocused();
    await press("ArrowLeft");
    expect(".o_app[data-menu-xmlid='test.sales']").toBeFocused();
});

test.tags("desktop");
test("typing opens the command palette in the menus namespace", async () => {
    await mountWebClient();
    await press("s");
    await waitFor(".o_command_palette");
    expect(".o_command_palette_search input").toHaveValue("s");
    expect(queryAllTexts(".o_command_palette .o_namespace")[0]).toBe("/");
});

test.tags("mobile");
test("on small screens, the sidebar's All Apps button opens the home menu", async () => {
    await mountWebClient();
    await openApp("test.sales");
    expect(".o_home_menu").toHaveCount(0);

    await contains(".o_main_navbar .o_menu_toggle").click();
    await contains(".o_sidebar_topbar a.btn-primary", { root: document.body }).click();
    await waitFor(".o_home_menu");
    await animationFrame();
    expect(".test_client_action").toHaveCount(0);
    await advanceTime(500); // the sidebar leave transition
    expect(queryAll(".o_app_menu_sidebar", { root: document.body })).toHaveLength(0);
});
