// js/app/vm/donateViewModel.js
// KnockoutJS viewmodel for the Donate section: wallets with address + URL template and host interop.

var DonateViewModel = function (app, params) {
    var self = this;

    self.app = app;
    params = params || {};

    function createWallet(w) {
        var wallet = {
            name: w.name,
            symbol: w.symbol,
            iconUrl: w.iconUrl,
            address: w.address,
            urlTemplate: w.urlTemplate,
            isCoin: w.isCoin,
            url: w.url,
            note: w.note
        };

        wallet.resolvedUrl = ko.pureComputed(function () {
            var tpl = wallet.urlTemplate || '';
            var addr = wallet.address || '';
            return tpl.replace('{address}', encodeURIComponent(addr));
        });

        // Per-row inline notice state
        wallet.noticeVisible = ko.observable(false);
        wallet.noticeText = ko.observable("");
        wallet.noticeFading = ko.observable(false);
        wallet.showInlineNotice = function (text, opts) {
            opts = opts || {};
            var visibleMs = opts.visibleMs || 1400;
            var fadeMs = opts.fadeMs || 600;

            wallet.noticeText(text);
            wallet.noticeFading(false);
            wallet.noticeVisible(true);

            setTimeout(function () {
                wallet.noticeFading(true);
                setTimeout(function () {
                    wallet.noticeVisible(false);
                    wallet.noticeFading(false);
                }, fadeMs);
            }, visibleMs);
        };

        return wallet;
    }

    var defaultWallets = [
        // Example items in self.wallets (non-coin):
        { name: 'PayPal', iconUrl: 'img/payments/paypal-128.png', url: 'https://paypal.me/lefthandenterprises', isCoin: false, note: 'LeftHandEnterprises' },
        { name: 'Cash App', iconUrl: 'img/payments/cashapp-128.png', url: 'https://cash.app/$LeftHandEnterprises', isCoin: false, note: '$LeftHandEnterprises' },

        {
            name: 'Bitcoin',
            symbol: 'BTC',
            address: 'bc1qfrsp5z478svmwsskkmdej0qnsn2l4gxzpkfkc5',
            urlTemplate: 'https://www.blockchain.com/btc/address/{address}',
            iconUrl: 'img/coins/btc.png',
            isCoin: true
        },
        {
            name: 'Ethereum',
            symbol: 'ETH',
            address: '0xA9F10eAdf8586a1D1A37325e29075f8d3E021D6c',
            urlTemplate: 'https://etherscan.io/address/{address}',
            iconUrl: 'img/coins/eth.png',
            isCoin: true
        },
        {
            name: 'Tether',
            symbol: 'USDT',
            address: '0xA9F10eAdf8586a1D1A37325e29075f8d3E021D6c',
            urlTemplate: 'https://etherscan.io/token/0xdac17f958d2ee523a2206206994597c13d831ec7?a={address}',
            iconUrl: 'img/coins/usdt.png',
            isCoin: true
        },
        {
            name: 'USD Coin',
            symbol: 'USDC',
            address: '0xA9F10eAdf8586a1D1A37325e29075f8d3E021D6c',
            urlTemplate: 'https://etherscan.io/token/0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48?a={address}',
            iconUrl: 'img/coins/usdc.png',
            isCoin: true
        },
        {
            name: 'Binance Coin',
            symbol: 'BNB',
            address: '0xA9F10eAdf8586a1D1A37325e29075f8d3E021D6c',
            urlTemplate: 'https://bscscan.com/address/{address}',
            iconUrl: 'img/coins/bnb.png',
            isCoin: true
        },
        {
            name: 'XRP',
            symbol: 'XRP',
            address: 'rwT7FEtJBUUAtGgixixG7rvgLb6GvWxrW4',
            urlTemplate: 'https://xrpscan.com/account/{address}',
            iconUrl: 'img/coins/xrp.png',
            isCoin: true
        },
        {
            name: 'Dogecoin',
            symbol: 'DOGE',
            address: 'DN7XUZ89hxf21RDSPytJgQqnbbsNDAS88r',
            urlTemplate: 'https://dogechain.info/address/{address}',
            iconUrl: 'img/coins/doge.png',
            isCoin: true
        },
        {
            name: 'Litecoin',
            symbol: 'LTC',
            address: 'ltc1qdruymcyl35y9t6t8fl2am06ekt5ekph7tre4ty',
            urlTemplate: 'https://blockchair.com/litecoin/address/{address}',
            iconUrl: 'img/coins/ltc.png',
            isCoin: true
        },
        {
            name: 'Cardano',
            symbol: 'ADA',
            address: 'addr1q8ttnwgph73dy8wrjlnc4qwz9g6yk04as596vcrpa9hgf8460vmxj9pzteruwzvcr2wkkaky6hmvptpw76qakyzj0kjq46mrnp',
            urlTemplate: 'https://cardanoscan.io/address/{address}',
            iconUrl: 'img/coins/ada.png',
            isCoin: true
        },
        {
            name: 'Tron',
            symbol: 'TRX',
            address: 'TBrg7gJ3gkRMMu5AFdZWZp5LweMxCHQQrX',
            urlTemplate: 'https://tronscan.org/#/address/{address}',
            iconUrl: 'img/coins/trx.png',
            isCoin: true
        }
    ];



    var seed = (params.wallets || defaultWallets).map(createWallet);
    self.wallets = ko.observableArray(seed);

    self.columns = [
        { key: 'icon', title: '' },
        { key: 'name', title: 'Name' },
        { key: 'symbol', title: 'Symbol' },
        { key: 'address', title: 'Address' },
        { key: 'actions', title: 'Actions' }
    ];

    function asBool(v) {
        v = ko.unwrap(v);                         // works for observables and plain values
        if (typeof v === 'string') v = v.trim().toLowerCase();
        if (v === 'true') return true;
        if (v === 'false') return false;
        return !!v;                               // numbers/booleans/undefined -> boolean
    }

    // ✅ Coins only
    self.walletsCrypto = ko.pureComputed(() => {
        const list = self.wallets();              // IMPORTANT: unwrap the observableArray
        return list.filter(w => asBool(w.isCoin));
    });

    // (optional) Non-coins
    self.walletsNonCrypto = ko.pureComputed(() => {
        const list = self.wallets();
        return list.filter(w => !asBool(w.isCoin));
    });

    // Send a { Command, Details, RequestId } envelope to the host
    function sendEnvelope(command, details) {
        var rid = (crypto.randomUUID && crypto.randomUUID()) ? crypto.randomUUID() : String(Date.now());
        var env = { Command: command, Details: details || {}, RequestId: rid };

        // Preferred: use the app's helper if present (it already uses Details in your app)
        if (self.app && typeof self.app.sendDotnetCommand === "function") {
            self.app.sendDotnetCommand(command, details);
            return true;
        }

        // Photino direct
        if (window.external && typeof window.external.sendMessage === "function") {
            window.external.sendMessage(JSON.stringify(env));
            return true;
        }

        // WebView2 fallback (if you ever host in it)
        if (window.chrome && window.chrome.webview && typeof window.chrome.webview.postMessage === "function") {
            window.chrome.webview.postMessage(JSON.stringify(env));
            return true;
        }

        return false;
    }


    self.openInHost = function (wallet) {
        var url = null;

        if (wallet.isCoin) {
            url = wallet.resolvedUrl();
        }
        else {
            url = wallet.url;
        }

        var details = { url: url, symbol: wallet.symbol, name: wallet.name, address: wallet.address };

        if (!sendEnvelope("OpenUrl", details)) {
            // Last resort if running in a normal browser (Photino ignores window.open)
            try { window.open(url, "_blank", "noopener,noreferrer"); } catch (_) { /* no-op */ }
        }
    };

    self.copyAddressInHost = function (wallet) {
        // If host implements CopyText, prefer native clipboard
        if (sendEnvelope("CopyText", { text: wallet.address, symbol: wallet.symbol, name: wallet.name })) {
            wallet.showInlineNotice("Copied");
            return;
        }

        // Browser fallbacks
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(wallet.address)
                .then(function () { wallet.showInlineNotice("Copied"); })
                .catch(function () { wallet.showInlineNotice("Copy failed"); });
        } else {
            try {
                var ta = document.createElement("textarea");
                ta.value = wallet.address;
                ta.style.position = "fixed";
                ta.style.opacity = "0";
                document.body.appendChild(ta);
                ta.select();
                var ok = document.execCommand("copy");
                document.body.removeChild(ta);
                wallet.showInlineNotice(ok ? "Copied" : "Copy failed");
            } catch (e) {
                wallet.showInlineNotice("Copy failed");
            }
        }
    };
};
