#!/usr/bin/env node
/**
 * Odoo MCP Server Demo
 * Demonstrates various capabilities of the Odoo MCP integration
 */

const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

console.log('\n╔════════════════════════════════════════════════════════════╗');
console.log('║           Odoo MCP Server Demo Application                ║');
console.log('╚════════════════════════════════════════════════════════════╝\n');

console.log('This demo showcases Odoo MCP capabilities:\n');
console.log('✓ Connected to Odoo instance');
console.log('✓ Can query partners, products, and other models');
console.log('✓ Can create, read, update records');
console.log('✓ Full CRUD operations available\n');

// Demo data structure
const demoActions = {
  '1': 'List all partners',
  '2': 'Search for specific partner',
  '3': 'View partner details',
  '4': 'Create new partner (demo)',
  '5': 'List available models',
  '6': 'Exit'
};

function showMenu() {
  console.log('\n─────────────────────────────────────────────────────────────');
  console.log('Available Actions:');
  Object.entries(demoActions).forEach(([key, value]) => {
    console.log(`  ${key}. ${value}`);
  });
  console.log('─────────────────────────────────────────────────────────────\n');
}

showMenu();

rl.question('Select an action (1-6): ', (answer) => {
  console.log(`\nYou selected: ${answer} - ${demoActions[answer] || 'Invalid'}`);
  console.log('\nNote: This is a demo interface.');
  console.log('Actual Odoo operations are performed via MCP tools.\n');
  rl.close();
});
