import Foundation
import Testing
@testable import Anycast

/// T8 paywall plan selection + carousel autoplay (05 §6.1 S21 / 03 §2.14):
/// pure model, no store calls.
@MainActor
struct PaywallPlanSelectionTests {

    // MARK: - Plan selection (states/user.dart:268, login.dart:577-645)

    @Test("iOS default chosen plan is anycast_monthly (isAndroid else branch)")
    func defaultSelection() {
        #expect(LoginPageModel.PlanSelection.iOSDefaultPlanID == "anycast_monthly")
        let selection = LoginPageModel.PlanSelection()
        #expect(selection.chosenPlanID == "anycast_monthly")
    }

    @Test("Tap selection flips the chosen card (login.dart:600-602)")
    func selectionFlip() {
        var selection = LoginPageModel.PlanSelection()
        let monthly = LoginPageModel.PlanCard(
            productID: "anycast_monthly", period: .monthly, priceString: "$2.99"
        )
        let annual = LoginPageModel.PlanCard(
            productID: "anycast_annual", period: .annual, priceString: "$19.99"
        )
        #expect(selection.isSelected(monthly))
        #expect(!selection.isSelected(annual))

        selection.choose("anycast_annual")
        #expect(!selection.isSelected(monthly))
        #expect(selection.isSelected(annual))
    }

    @Test("Selected package lookup drives \"Invalid plan\" (login.dart:478-501)")
    func selectedCardLookup() {
        var selection = LoginPageModel.PlanSelection()
        let plans = [
            LoginPageModel.PlanCard(
                productID: "anycast_monthly", period: .monthly, priceString: "$2.99"
            ),
            LoginPageModel.PlanCard(
                productID: "anycast_annual", period: .annual, priceString: "$19.99"
            ),
        ]
        #expect(selection.selectedCard(available: plans)?.productID == "anycast_monthly")

        selection.choose("anycast_annual")
        #expect(selection.selectedCard(available: plans)?.productID == "anycast_annual")

        // A chosen id with no matching package → Invalid plan dialog.
        selection.choose("anycast_plus:monthly") // the Android-only id
        #expect(selection.selectedCard(available: plans) == nil)
        #expect(selection.selectedCard(available: []) == nil)
    }

    @Test("Card copy: title/unit/price/caption (login.dart:578-640)")
    func cardCopy() {
        let monthly = LoginPageModel.PlanCard(
            productID: "anycast_monthly", period: .monthly, priceString: "$2.99"
        )
        #expect(monthly.title == "Monthly")
        #expect(monthly.unit == "Month")
        #expect(monthly.priceLine == "$2.99/Month")
        #expect(monthly.autoRenewalCaption == "Auto Renewal\n$2.99/month")

        let annual = LoginPageModel.PlanCard(
            productID: "anycast_annual", period: .annual, priceString: "€19.99"
        )
        #expect(annual.title == "Yearly")
        #expect(annual.unit == "Year")
        #expect(annual.priceLine == "€19.99/Year")
        #expect(annual.autoRenewalCaption == "Auto Renewal\n€19.99/year")
    }

    // MARK: - PlusIntro title (login.dart:660-663)

    @Test("PlusIntro title switches on \"annual\" substring")
    func plusIntroTitle() {
        #expect(
            LoginPageModel.plusIntroTitle(chosenPlanID: "anycast_monthly")
                == "Anycast Plus (Monthly)"
        )
        #expect(
            LoginPageModel.plusIntroTitle(chosenPlanID: "anycast_annual")
                == "Anycast Plus (Annually)"
        )
        // The Dart matches a substring, not the package type.
        #expect(
            LoginPageModel.plusIntroTitle(chosenPlanID: "promo_annual_2")
                == "Anycast Plus (Annually)"
        )
        #expect(
            LoginPageModel.plusIntroTitle(chosenPlanID: "")
                == "Anycast Plus (Monthly)"
        )
    }

    // MARK: - Carousel autoplay tick model (login.dart:426-447)

    @Test("Autoplay advances every tick and wraps after the last slide")
    func carouselTickWraps() {
        var model = LoginPageModel.CarouselAutoplay()
        #expect(model.pageIndex == 0)
        model.tick()
        #expect(model.pageIndex == 1)
        model.tick()
        #expect(model.pageIndex == 0)
        model.tick()
        #expect(model.pageIndex == 1)
    }

    @Test("Carousel constants mirror carousel_slider defaults")
    func carouselConstants() {
        #expect(LoginPageModel.CarouselAutoplay.slideCount == 2)
        #expect(LoginPageModel.CarouselAutoplay.autoplayInterval == 4)
    }

    @Test("Autoplay pauses while touched and resumes on release")
    func carouselPauseResume() {
        var model = LoginPageModel.CarouselAutoplay()
        model.pause()
        model.tick()
        model.tick()
        #expect(model.pageIndex == 0) // frozen during the drag
        model.resume()
        model.tick()
        #expect(model.pageIndex == 1)
    }

    @Test("User scroll updates the tracked page (modulo wrap)")
    func carouselUserPage() {
        var model = LoginPageModel.CarouselAutoplay()
        model.setUserPage(1)
        #expect(model.pageIndex == 1)
        model.setUserPage(2) // out of range clamps by wrapping
        #expect(model.pageIndex == 0)
    }
}
