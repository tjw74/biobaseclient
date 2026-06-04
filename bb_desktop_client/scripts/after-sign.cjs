module.exports = async function afterSign() {
  if (!process.env.CSC_LINK && !process.env.WIN_CSC_LINK) {
    console.log('Biobase: no Windows signing certificate configured; unsigned build mode.');
  }
};
