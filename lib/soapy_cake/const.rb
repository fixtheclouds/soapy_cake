module SoapyCake
  module Const
    CONSTS = {
      account_status_id: {
        active: 1,
        inactive: 2,
        pending: 3,
      },
      offer_status_id: {
        public: 1,
        private: 2,
        apply_to_run: 3,
        inactive: 4,
      },
      offer_type_id: {
        hosted: 1,
        host_n_post: 2,
        third_party: 3,
      },
      currency_id: {
        usd: 1,
        eur: 2,
        gbd: 3,
        aud: 4,
        cad: 5,
      },
      payment_setting_id: {
        system_default: 1,
        offer_currency: 2,
        affiliate_currency: 3,
      },
      price_format_id: {
        cpa: 1,
        cpc: 2,
        cpm: 3,
        fixed: 4,
        revshare: 5,
      },
      conversion_behaviour_id: {
        system: 0,
        adv_off: 1,
        adv_no_aff: 2,
        ignore: 3,
        no_adv_aff: 4,
        no_adv_no_aff: 5,
      },
      cap_type_id: {
        click: 1,
        conversion: 2,
      },
      cap_interval_id: {
        disabled: 0,
        daily: 1,
        weekly: 2,
        monthly: 3,
      }
    }
  end
end
