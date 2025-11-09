# IVM Token Deployment

IVM Token هو عقد ERC-20 يدير التوزيعات، محافظ الاستحقاق، وحساب الحرق بطريقة آلية. يوضح هذا المستودع كيفية ضبط البيئة، اختبار العقد محليًا، ونشره على شبكات مثل Sepolia أو Mainnet.

## المتطلبات

- Node.js 18+
- حساب على Alchemy أو Infura للحصول على رابط RPC لشبكة Sepolia/Mainnet
- مفتاح خاص للمحفظة التي ستنشر العقد (يفضل استخدام محفظة منفصلة أو جهازية)

## الإعداد

1. ثبّت الاعتمادات:
   ```bash
   npm install
   ```
2. أنشئ ملف `.env` (أو عدّل الموجود) بالقيم الفعلية:
   ```env
   PRIVATE_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YourKey
   MAINNET_RPC_URL=https://mainnet.infura.io/v3/YourKey
   ETHERSCAN_API_KEY=YourEtherscanKey

   COMMUNITY_WALLET=0x7b81747dc97AFB180cF3B4C2B602d9f9833Cf62c
   MARKETING_WALLET=0xa4847C23d9010127719D3c8896D503DBc4498CEc
   DEVELOPMENT_WALLET=0x1158870aF07B48F06242dA3FEF5A37C407B3ab68
   TEAM_WALLET=0x70B4c5be45106D02606B8c37399fD44b1674bc54
   RESERVE_WALLET=0x891aADE6fa998bCABC7a4dBC0A7324589d503Eba
   LOYALTY_WALLET=0xD11658aE686003aAC530ACfFd9Df64a117C52C15
   ```
   > احتفظ بالملف محليًا ولا ترفعه للمستودع.

3. تأكد من أن العقد يُبنى بنجاح:
   ```bash
   npx hardhat compile
   ```

## اختبار محلي

يمكنك تشغيل شبكة Hardhat المحلية ونشر العقد للتأكد من تدفق التهيئة كاملاً:
```bash
npx hardhat node
# في جلسة أخرى:
npx hardhat run scripts/deploy.js --network localhost
```

## النشر على شبكة اختبار (Sepolia)

1. تأكد من توفر ETH تجريبي في عنوان المالك.
2. نفّذ:
   ```bash
   npx hardhat run scripts/deploy.js --network sepolia
   ```
   سيقوم السكربت تلقائيًا بانتظار التأكيدات ثم يرسل أمر التوثيق إلى Etherscan طالما أن `ETHERSCAN_API_KEY` معرف في `.env`. ستظهر رسالة "Verification complete." عند النجاح.
3. إذا احتجت إعادة التوثيق لأي سبب، يمكنك دائمًا تشغيل:
   ```bash
   npx hardhat verify --network sepolia <contract-address>
   ```

## النشر على الشبكة الرئيسية (Ethereum Mainnet)

1. تأكد من تعبئة `MAINNET_RPC_URL` ووجود رصيد ETH كافٍ لتكاليف النشر.
2. نفّذ:
   ```bash
   npx hardhat run scripts/deploy.js --network mainnet
   ```
   يقوم السكربت بالانتظار لخمس تأكيدات قبل محاولة التوثيق التلقائي. إن ظهرت رسالة تفيد بأن العقد موثّق مسبقًا فهذا يعني أن العملية تمت في تنفيذ سابق.

## بعد النشر

- استخدم `npx hardhat console --network <network>` لقراءة القيم مثل `totalTokensSentToDead()` أو `allocationsInitialized()`.
- لتفعيل الحرق التلقائي أو ضبط زوج السيولة:
  ```js
  await ivm.setAutoBurn(true, 100); // 1%
  await ivm.setMarketPair("0xPairAddress");
  ```
- استخدم `burnWallet()` لقراءة عنوان المحفظة الميتة الافتراضية (`0x000000000000000000000000000000000000dEaD`). يمكن للمالك تحديثها بـ `setBurnWallet(address)` إذا أراد عنوانًا مخصصًا للتتبع، وسيتم إطلاق حدث `BurnWalletUpdated`.
- الحصص الموقوفة في محافظ الـvesting (التسويق، التطوير، الفريق، الاحتياطي) تُفرج تلقائيًا فور حلول موعدها عبر دالة داخلية تُستدعى في كل تحويل أو يدويًا عن طريق `releaseUnlockedAllocations()`. كل عملية إطلاق تسجَّل في حدث `AllocationReleased`.
- نظام الحرق يتوقف تلقائيًا عندما يصل المعروض الفعلي المتداول إلى 21,000,000 IVM (أي بعد حرق/إرسال 479,000,000 IVM إلى العناوين الميتة). بعد الوصول لهذا الحد ستفشل أي محاولة حرق إضافية أو يتم تجاهلها آليًا.
- تابع عمليات الاستحقاق والحرق عبر الأحداث `AutoBurn`, `BuyBurn`, `ManualBurn`, و `AllocationsInitialized`.

## ملاحظات أمنية

- لا تشارك مفاتيحك الخاصة أو ملف `.env`.
- راجع جميع العناوين قبل النشر على الشبكة الرئيسية.
- استخدم محافظ متعددة التوقيع أو حلول حراسة عند الحاجة لتحسين الأمان.
