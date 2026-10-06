'use strict';

const express = require('express');
const {
  handleWebhook,
  handleOrderWebhook,
  getWebhookResult,
} = require('../controllers/webhooks.controller');
const { requireStaff } = require('../lib/require-staff');

const router = express.Router();

// The POS polls this for payment results; gateways only POST.
router.get('/:gateway/:orderKey', requireStaff, getWebhookResult);
router.post('/:gateway/:orderKey', handleOrderWebhook);
router.post('/:gateway', handleWebhook);

module.exports = router;
